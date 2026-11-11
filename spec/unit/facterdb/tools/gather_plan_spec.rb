# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'puppetlabs/facterdb/tools'

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Puppetlabs::FacterDB::Tools::GatherPlan do
  let(:tools) { Puppetlabs::FacterDB::Tools }
  let(:facts_dir) { Dir.mktmpdir }
  let(:platforms) { tools::Platforms.load }
  let(:version_map) { tools::VersionMap.load }
  let(:page) { tools::ReleaseNotes.parse('<h2>Facter 4.30.0</h2><p>Released December 2026 and shipped with Puppet Core 9.2.0.</p>') }
  let(:calls) { [] }
  let(:release_notes) { -> { page.tap { calls << :notes } } }
  let(:gem_versions) { ['4.12.0', '4.13.0', '4.14.0'] }
  let(:gem_index) { -> { Struct.new(:versions).new(gem_versions).tap { calls << :gems } } }

  after(:each) { FileUtils.remove_entry(facts_dir) }

  def write_fact(minor, name, version)
    FileUtils.mkdir_p(File.join(facts_dir, minor))
    File.write(File.join(facts_dir, minor, "#{name}.facts"), JSON.generate('facterversion' => version))
  end

  def plan(event: 'workflow_dispatch', version: nil, ids: nil)
    described_class.new(
      event: event, facter_version: version, platforms_input: ids, platforms: platforms, version_map: version_map,
      release_notes: release_notes, gem_index: gem_index, facts_dir: facts_dir
    ).call
  end

  describe 'dispatch' do
    it 'resolves a mapped version without map change' do
      result = plan(version: '4.23.0')
      expect([result.version, result.agent_major, result.agent, result.map_changed]).to eq(['4.23.0', '9', '9.1.3', false])
    end

    it 'covers all active platforms when none are given' do
      expect(plan(version: '4.23.0').selected_ids).to eq(platforms.active.map(&:id))
    end

    it 'never calls the network callables for a mapped version' do
      plan(version: '4.23.0')
      expect(calls).to be_empty
    end

    ["4.23.0\nfoo", '4.23', 'v4.23.0', '', nil, '4.11.0'].each do |bad|
      it "rejects #{bad.inspect}" do
        expect { plan(version: bad) }.to raise_error(ArgumentError)
      end
    end

    it 'resolves an unmapped version from the release notes page' do
      result = plan(version: '4.30.0')
      expect([result.agent, result.map_changed, result.agents]).to eq(['9.2.0', true, { '9' => '9.2.0' }])
    end

    it 'fails fast when the version is in neither map nor page' do
      expect { plan(version: '4.31.0') }.to raise_error(ArgumentError, 'Facter 4.31.0 is not in config/facter_versions.yml or on the release notes page')
    end

    it 'restricts the matrix to the given platform ids' do
      result = plan(version: '4.23.0', ids: 'ubuntu-24.04-x86_64, windows-2025-x86_64')
      expect(result.matrix['include'].map { |row| row['id'] }).to eq(['ubuntu-24.04-x86_64', 'windows-2025-x86_64'])
    end

    ['bad;rm', 'no-such-1-x86_64', 'windows-2019-x86_64'].each do |bad|
      it "rejects platform input #{bad.inspect}" do
        expect { plan(version: '4.23.0', ids: bad) }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'schedule' do
    before(:each) { write_fact('4.12', 'ubuntu-24.04-x86_64', '4.12.0') }

    it 'picks the oldest missing version' do
      expect(plan(event: 'schedule').version).to eq('4.13.0')
    end

    it 'resolves the agent from the map without map change' do
      result = plan(event: 'schedule')
      expect([result.agent, result.map_changed]).to eq(['8.13.0', false])
    end

    it 'ignores facter_version and platforms_input' do
      result = plan(event: 'schedule', version: 'garbage', ids: 'bad;rm')
      expect([result.version, result.selected_ids]).to eq(['4.13.0', platforms.active.map(&:id)])
    end

    context 'when every gem version is stored' do
      let(:gem_versions) { ['4.12.0'] }

      it 'is a no-op' do
        result = plan(event: 'schedule')
        expect([result.noop?, result.noop_reason]).to eq([true, 'No new Facter release'])
      end
    end

    context 'when only older patches than stored exist' do
      let(:gem_versions) { ['4.13.0'] }

      it 'never downgrades' do
        write_fact('4.13', 'ubuntu-24.04-x86_64', '4.13.1')
        expect(plan(event: 'schedule')).to be_noop
      end
    end

    context 'when the missing version is not on the page' do
      let(:gem_versions) { ['4.12.0', '4.31.0'] }

      it 'is a no-op naming the version' do
        expect(plan(event: 'schedule').noop_reason).to match(%r{4\.31\.0.*not on the release notes page yet})
      end
    end

    context 'when the missing version is on the page but not in the map' do
      let(:gem_versions) { ['4.12.0', '4.30.0'] }

      it 'resolves from the page with map change' do
        result = plan(event: 'schedule')
        expect([result.version, result.agent, result.map_changed]).to eq(['4.30.0', '9.2.0', true])
      end
    end

    context 'when the page lists the version without a Core agent' do
      let(:gem_versions) { ['4.12.0', '4.30.0'] }
      let(:page) { tools::ReleaseNotes.parse('<h2>Facter 4.30.0</h2><p>Released December 2026.</p>') }

      it 'is a no-op' do
        expect(plan(event: 'schedule').noop_reason).to match(%r{not on the release notes page yet})
      end
    end
  end

  describe 'other events' do
    ['pull_request', 'push', nil].each do |event|
      it "rejects #{event.inspect}" do
        expect { plan(event: event, version: '4.23.0') }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.stored_versions' do
    it 'returns the highest stored facterversion per major.minor' do
      write_fact('4.12', 'a', '4.12.0')
      write_fact('4.12', 'b', '4.12.1')
      expect(described_class.stored_versions(facts_dir)).to eq('4.12' => '4.12.1')
    end

    it 'skips malformed files' do
      FileUtils.mkdir_p(File.join(facts_dir, '4.12'))
      File.write(File.join(facts_dir, '4.12', 'bad.facts'), '{not json')
      expect(described_class.stored_versions(facts_dir)).to eq({})
    end
  end

  describe '.missing' do
    it 'excludes versions below the minimum and not newer than stored' do
      expect(described_class.missing(['4.11.0', '4.12.0', '4.12.2', '4.13.0'], '4.12' => '4.12.1')).to eq(['4.12.2', '4.13.0'])
    end
  end

  describe 'rake gather:plan' do
    let(:output) { File.join(facts_dir, 'github_output') }
    let(:rake) do
      env = { 'GITHUB_EVENT_NAME' => 'workflow_dispatch', 'INPUT_FACTER_VERSION' => '4.23.0', 'INPUT_PLATFORMS' => '', 'GITHUB_OUTPUT' => output }
      Open3.capture3(env, RbConfig.ruby, '-S', 'rake', 'gather:plan', chdir: tools::REPO_ROOT)
    end

    it 'writes the six outputs on separate lines' do
      rake
      keys = File.readlines(output).map { |line| line.split('=', 2).first }
      expect(keys).to include('version', 'agent_major', 'agent', 'map_changed', 'matrix', 'selected_ids')
    end

    it 'exits non-zero for an invalid version' do
      env = { 'GITHUB_EVENT_NAME' => 'workflow_dispatch', 'INPUT_FACTER_VERSION' => '4.23', 'GITHUB_OUTPUT' => output }
      _out, _err, status = Open3.capture3(env, RbConfig.ruby, '-S', 'rake', 'gather:plan', chdir: tools::REPO_ROOT)
      expect(status).not_to be_success
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
