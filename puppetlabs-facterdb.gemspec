# frozen_string_literal: true

require_relative 'lib/puppetlabs/facterdb/version'

Gem::Specification.new do |s|
  s.name        = 'puppetlabs-facterdb'
  s.version     = Puppetlabs::FacterDB::Version::STRING
  s.authors     = ['Perforce']
  s.homepage    = 'https://github.com/puppetlabs/puppetlabs-facterdb'
  s.summary     = 'Database of OS facts keyed by the real Facter version'
  s.description = 'Contains facts from many Facter versions on many operating systems, stored and looked up under the real Facter version that produced them.'
  s.licenses    = ['Apache-2.0']

  s.files       = Dir['lib/**/*.rb', 'exe/*', 'facts/**/*.facts', 'facts/PROVENANCE.md', 'facts/seed-manifest.json', 'LICENSE', 'NOTICE', 'README.md', 'CHANGELOG.md']
  s.bindir      = 'exe'
  s.executables = ['puppetlabs-facterdb']

  s.required_ruby_version = Gem::Requirement.new('>= 3.1')
  s.metadata['rubygems_mfa_required'] = 'true'

  s.add_dependency 'jgrep', '~> 1.5', '>= 1.5.4'
end
