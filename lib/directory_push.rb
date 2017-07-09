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
      :rsync_options,
      :settings_dir_path
    )

    FILTER_FILE_NAME = '.rsync-filter'
      DEFAULT_RSYNC_OPTIONS = [
      '--verbose',
      '--archive',
      '--compress',
      '--progress',
      %Q{--exclude-from '#{FILTER_FILE_NAME}'},
      %Q{--timeout '9999'}
    ]
    GUARDFILE_TEXT = %q{
require 'yaml'
require 'guard/compat/plugin'
require 'rsync'

config = YAML.load(File.read(File.join(File.dirname(__FILE__), 'config.yml')))
$rsync_options = config.delete(:rsync)
$rsync_options << '--delete'
$source = config.delete(:source)
ignore_pattern = config.delete(:ignore)
$remote = %Q{#{config.delete(:user)}@#{config.delete(:remote_address)}:"#{config.delete(:destination)}"}

module ::Guard
  class DirectoryPush < Plugin
    private
    def sync()
      Compat::UI.info %Q{Guard::DirectoryPush source: "#{$source}", destination: "#{$remote}", options: #{$rsync_options}}
      result = Rsync.run $source, $remote, $rsync_options
      if result.success?
        result.changes.each do |change|
          Compat::UI.info "#{change.filename} (#{change.summary})"
        end
      else
        Compat::UI.error result.error
        raise result.error
      end
    end

    public

    alias_method :start, :sync
    alias_method :stop, :sync
    alias_method :reload, :sync
    alias_method :run_all, :sync
    def run_on_additions(paths)
      Compat::UI.info "Guard::DirectoryPush Files created: #{paths}"
      sync
    end
    def run_on_modifications(paths)
      Compat::UI.info "Guard::DirectoryPush Files changed: #{paths}"
      sync
    end
    def run_on_removals(paths)
      Compat::UI.info "Guard::DirectoryPush Files removed: #{paths}"
      sync
    end
  end
end

config[:verbose] = true
config[:cli] = '--color'
config[:sync_on_start] = true

directories [$source]
guard 'directory-push', config do
  watch %r{^.+$}
  if ignore_pattern
    ignore ignore_pattern
  end
end
}

    DEFAULT_USER = Etc.getlogin

    def initialize(
        directory_path,
        remote_address,
        user: DEFAULT_USER,
        path_on_remote: nil,
        pull: false,
        rsync_options: DEFAULT_RSYNC_OPTIONS,
        guard_ignore_pattern: nil,
        preserve_settings: false
    )
      if (
        remote_address.nil? ||
        remote_address.empty? ||
        remote_address == '~' ||
        remote_address == '$HOME'
      )
        raise ArgumentError.new(
          %Q{Remote address, "#{remote_address}", is invalid!}
        )
      end

      @directory_path = File.expand_path(directory_path, Dir.pwd)
      unless File.exists?(@directory_path)
        raise ArgumentError.new(
          %Q{Directory "#{@directory_path}" does not exist!}
        )
      end

      @user = user
      if @user.nil? || @user.empty?
        raise ArgumentError.new(%Q{User "#{@user}" is invalid!.})
      end

      @remote_address = remote_address
      @path_on_remote = path_on_remote || @directory_path
      @terminal = HighLine.new
      @pull = pull
      @rsync_options = rsync_options
      @guard_ignore_pattern = guard_ignore_pattern
      @preserve_settings = preserve_settings
      @settings_dir_path = File.join(
        Dir.pwd,
        ".#{directory_name}.directory_push-settings"
      )
    end

    def pull?() @pull end

    def directory_name() File.basename(@directory_path) end

    def ensure_setting_dir_present()
      unless File.directory?(settings_dir_path)
        @terminal.say("Creating settings directory, \"#{settings_dir_path}\".")
        FileUtils.mkdir(settings_dir_path)
      end
    end

    def filter_path() File.join(settings_dir_path, FILTER_FILE_NAME) end
    def config_path() File.join(settings_dir_path, 'config.yml') end
    def guardfile_path() File.join(settings_dir_path, 'Guardfile') end

    def ensure_filter_file_present()
      ensure_setting_dir_present
      @terminal.say("Creating rsync-filter file")
      gitignore = File.join(@directory_path, '.gitignore')
      if File.exists?(gitignore)
         @terminal.say(
          %Q{Using "#{gitignore}" as rsync-filter since they have the same format.}
        )
        FileUtils.cp(gitignore, filter_path)
      else
        FileUtils.touch(filter_path) unless File.exist?(filter_path)
      end
    end

    def config()
      {
        source: "#{@directory_path}/",
        user: @user,
        remote_address: @remote_address,
        destination: @path_on_remote,
        rsync: @rsync_options,
        ignore: @guard_ignore_pattern
      }
    end

    def config_to_yml() YAML.dump(config) end

    def ensure_config_file_present()
      ensure_setting_dir_present
      unless File.exist?(config_path)
        @terminal.say %Q{Creating config file in "#{config_path}".}
        File.open(config_path, 'w') { |f| f.print config_to_yml }
      end
    end

    def ensure_guardfile_present()
      ensure_setting_dir_present
      unless File.exist?(guardfile_path)
        @terminal.say %Q{Creating Guardfile in "#{guardfile_path}".}
        File.open(guardfile_path, 'w') { |f| f.print GUARDFILE_TEXT }
      end
    end

    def pull_from_remote(destination)
      source = "#{@user}@#{@remote_address}:#{@path_on_remote}"

      @terminal.say %Q{Pulling from "#{source}" and replacing the contents of "#{destination}".}

      sync source, destination
    end

    def sync(source, destination)
      result = Rsync.run source, destination, @rsync_options
      if result.success?
        result.changes.each do |change|
          @terminal.say "#{change.filename} (#{change.summary})"
        end
      else
        @terminal.say result.error
      end
    end

    def backup_dir_path(d)
      File.join settings_dir_path, "#{File.basename(d)}.bak"
    end

    def watch()
      ensure_config_file_present
      ensure_guardfile_present
      ensure_filter_file_present
      Dir.chdir settings_dir_path do |d|
        if pull?
          directory_path_bak = backup_dir_path(@directory_path)
          @terminal.say %Q{Backing up "#{@directory_path}" in "#{directory_path_bak}".}
          FileUtils.cp_r @directory_path, directory_path_bak

          pull_from_remote @directory_path
        else
          source = "#{@user}@#{@remote_address}:#{@path_on_remote}/"
          source_bak = backup_dir_path(@path_on_remote)

          @terminal.say %Q{Backing up "#{source}" in "#{source_bak}".}
          sync source, source_bak
        end

        @terminal.say "Starting Guard"
        command = "guard"
        @terminal.say command
        system command
      end

      unless @preserve_settings
        @terminal.say %Q{Removing settings directory, "#{settings_dir_path}".}
        FileUtils.rm_rf(settings_dir_path)
      end
    end
  end
end
