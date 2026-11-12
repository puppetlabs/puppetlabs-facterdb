# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'puppetlabs/facterdb/tools'

module VersionsTasks
  Tools = Puppetlabs::FacterDB::Tools

  module_function

  def update
    abort 'PUPPET_FORGE_TOKEN is not set' if ENV.fetch('PUPPET_FORGE_TOKEN', '').empty?

    map = Tools::FacterVersions.load
    index_versions = Tools::CoreIndex.new.facter_versions
    if map.unmapped(index_versions).empty?
      puts 'no new Facter versions'
      return
    end

    notes = Tools::ReleaseNotes.new(Tools::ReleaseNotes.fetch)
    added = map.update_from(index_versions, notes)
    map.write
    puts "added: #{added.join(', ')}"
  rescue Tools::ReleaseNotes::MissingVersion => e
    abort e.message
  end
end

namespace :versions do
  desc 'Add new Puppet Core Facter versions and their agents to config/facter_versions.yml'
  task :update do
    VersionsTasks.update
  end
end
