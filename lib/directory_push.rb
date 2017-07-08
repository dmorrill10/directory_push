require File.expand_path('../directory_push/version', __FILE__)
require 'highline'
require 'yaml'
require 'etc'
require 'fileutils'
require 'rsync'


module DirectoryPush
  class Cli
    attr_reader(
      :directory_path,
      :path_on_remote,
      :user,
      :remote_address,
      :rsync_options
    )

    FILTER_FILE_NAME = '.rsync-filter'
    DEFAULT_RSYNC_OPTIONS = [
      '-arv'
      '--progress'
      %W{--exclude-from '#{FILTER_FILE_NAME}'}
      %w{--timeout '9999'}
    ]
    GUARDFILE_TEXT = <<EOS
require 'yaml'

config = YAML.load(File.read(File.join(File.dirname(__FILE__), 'config.yml')))

directories [config['source']]
guard 'remote-sync',
        :source => config['source'],
        :destination => config['destination'],
        :user => config['user'],
        :remote_address => config['remote_address'],
        :verbose => true,
        :cli => "--color",
        :sync_on_start => true do
  watch %r{^.+$}
  if config['ignore']
    ignore config['ignore']
  end
end
EOS

    DEFAULT_USER = Etc.getlogin

    def initialize(
        directory_path,
        remote_address,
        user: DEFAULT_USER,
        path_on_remote: nil,
        pull: false,
        rsync_options: DEFAULT_RSYNC_OPTIONS,
        guard_ignore_pattern: nil
    )
      if remote_address.nil? || remote_address.empty?
        raise ArgumentError.new(
          %W{Remote address, "#{remote_address}", is invalid!}
        )
      end

      @directory_path = File.expand_path(directory_path, Dir.pwd)
      unless File.exists?(@directory_path)
        raise ArgumentError.new(
          %W{Directory "#{@directory_path}" does not exist!}
        )
      end
      @remote_address = remote_address
      @path_on_remote = path_on_remote || directory_name
      @terminal = HighLine.new
      @pull = pull
      @rsync_options = rsync_options
      @guard_ignore_pattern = guard_ignore_pattern
    end

    def pull?() @pull end

    def directory_name() File.basename(@directory_path) end

    def settings_dir_path(root = Dir.pwd)
      File.join(root, ".#{directory_name}.directory_push-settings")
    end

    def ensure_setting_dir_present()
      unless File.directory?(settings_dir_path)
        @terminal.say("Creating settings directory, \"#{settings_dir_path}\".")
        FileUtils.mkdir(settings_dir_path)
      end
    end

    def filter_path() File.join(settings_dir_path, FILTER_FILE_NAME) end
    def config_path() File.join(settings_dir_path, 'config.yml') end
    def guardfile_path() File.join(settings_dir_path, 'Guardfile') end

    def create_filter_file()
      ensure_setting_dir_present
      @terminal.say("Creating rsync-filter file")
      gitignore = File.join(@directory_path, '.gitignore')
      if File.exists?(gitignore)
         @terminal.say(
          %W{Using "#{gitignore}" as rsync-filter since they have the same format.}
        )
        FileUtils.cp(gitignore, filter_path)
      else
        unless File.exist?(filter_path)
          File.open(filter_path, 'w') do |f| end
        end
      end
    end

    def config()
      {
        source: => "#{@directory_path}/",
        user: => @user,
        directory_name: => directory_name,
        remote_address: => @remote_address,
        destination: => @path_on_remote,
        rsync: => @rsync_options,
        ignore: => @guard_ignore_pattern
      }
    end

    def config_to_yml() YAML.dump(config) end

    def ensure_config_file_present()
      ensure_setting_dir_present
      unless File.exist?(config_path)
        @terminal.say %W{Creating config file in "#{config_path}".}
        File.open(config_path, 'w') { |f| f.print config_to_yml }
      end
    end

    def ensure_guardfile_present()
      ensure_setting_dir_present
      unless File.exist?(guardfile_path)
        @terminal.say %W{Creating Guardfile in "#{guardfile_path}".}
        File.open(guardfile_path, 'w') { |f| f.print GUARDFILE_TEXT }
      end
    end

    def watch()
      ensure_config_file_present
      ensure_guardfile_present
      Dir.chdir settings_dir_path do |d|
        if pull?
          destination = @directory_path
          source = "#{@user}@#{@remote_address}:#{@path_on_remote}"

          @terminal.say %W{Pulling from "#{source}" and replacing the contents of "#{destination}".}

          Rsync.run(source, destination, @rsync_options) do |result|
            if result.success?
              result.changes.each do |change|
                @terminal.say "#{change.filename} (#{change.summary})"
              end
            else
              @terminal.say result.error
            end
          end
        end

        @terminal.say "Starting Guard"
        command = "bundle exec guard"
        @terminal.say command
        system command
      end

      @terminal.say %W{Removing settings directory, "#{settings_dir_path}".}
      FileUtils.rm_rf(settings_dir_path)
    end
  end
end
