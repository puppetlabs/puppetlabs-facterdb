# frozen_string_literal: true

require 'spec_helper'
require 'puppetlabs/facterdb/tools'

RSpec.describe 'config/facter_versions.yml' do # rubocop:disable RSpec/DescribeClass
  let(:path) { File.join(Puppetlabs::FacterDB::Tools::REPO_ROOT, 'config', 'facter_versions.yml') }
  let(:map) { Puppetlabs::FacterDB::Tools::VersionMap.load(path) }
  let(:fixture) { File.join(Puppetlabs::FacterDB::Tools::REPO_ROOT, 'spec', 'fixtures', 'release_notes', 'release_notes_facter.html') }
  let(:notes) { Puppetlabs::FacterDB::Tools::ReleaseNotes.parse(File.read(fixture)) }

  it 'only lists versions at or above the minimum' do
    expect(map.versions.map { |v| Gem::Version.new(v) }).to all(be >= Puppetlabs::FacterDB::Tools::VersionMap::MIN_VERSION)
  end

  it 'is in canonical dump form' do
    expect(map.dump).to eq(File.read(path))
  end

  it 'agrees with the release notes page for every version' do
    mismatches = map.versions.reject { |v| notes.agents_for(v) == map.agents_for(v) }
    expect(mismatches).to eq([])
  end

  it 'covers every Core release the page lists at or above the minimum' do
    listed = notes.versions.select { |v| Gem::Version.new(v) >= Puppetlabs::FacterDB::Tools::VersionMap::MIN_VERSION && !notes.agents_for(v).empty? }
    expect(map.versions).to match_array(listed)
  end
end
