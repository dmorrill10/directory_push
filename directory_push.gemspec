# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'directory_push/version'

Gem::Specification.new do |spec|
  spec.name          = 'directory_push'
  spec.version       = DirectoryPush::VERSION
  spec.authors       = ['Dustin Morrill']
  spec.email         = ['dmorrill10@gmail.com']
  spec.summary       = 'DirectoryPush: Push file changes to a remote server.'
  spec.description   = ''
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'guard'
  spec.add_dependency 'guard-shell'
  spec.add_dependency 'guard-compat'
  spec.add_dependency 'highline'
  spec.add_dependency "rsync"

  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake'
end
