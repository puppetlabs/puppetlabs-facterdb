# frozen_string_literal: true

require_relative 'lib/perforce/facterdb/version'

Gem::Specification.new do |s|
  s.name        = 'perforce-facterdb'
  s.version     = Perforce::FacterDB::Version::STRING
  s.authors     = ['Perforce']
  s.homepage    = 'https://github.com/puppetlabs/perforce-facterdb'
  s.summary     = 'Database of OS facts keyed by the real Facter version'
  s.description = 'Contains facts from many Facter versions on many operating systems, stored and looked up under the real Facter version that produced them.'
  s.licenses    = ['Apache-2.0']

  s.files       = Dir['lib/**/*.rb', 'exe/*', 'facts/**/*.facts', 'LICENSE', 'README.md', 'CHANGELOG.md']
  s.bindir      = 'exe'
  s.executables = ['perforce-facterdb']

  s.required_ruby_version = Gem::Requirement.new('>= 3.1')
  s.metadata['rubygems_mfa_required'] = 'true'

  s.add_dependency 'jgrep', '~> 1.5', '>= 1.5.4'
end
