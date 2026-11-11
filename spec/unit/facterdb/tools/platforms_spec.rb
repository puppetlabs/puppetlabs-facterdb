# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::Platforms do
  let(:root) { Dir.mktmpdir }

  def core
    [
      { 'os' => 'ubuntu', 'release' => '24.04', 'arch' => 'x86_64' },
      { 'os' => 'windows', 'release' => '2025', 'arch' => 'x86_64' },
    ]
  end

  def ubuntu
    {
      'id' => 'ubuntu-24.04-x86_64', 'os' => 'ubuntu', 'release' => '24.04', 'arch' => 'x86_64',
      'family' => 'linux', 'backend' => 'container', 'runner' => 'ubuntu-24.04',
      'image' => 'litmusimage/ubuntu:24.04', 'repo_id' => 'noble'
    }
  end

  def windows
    {
      'id' => 'windows-2025-x86_64', 'os' => 'windows', 'release' => '2025', 'arch' => 'x86_64',
      'family' => 'windows', 'backend' => 'runner', 'runner' => 'windows-2025'
    }
  end

  def skipped
    {
      'id' => 'windows-2019-x86_64', 'os' => 'windows', 'release' => '2019', 'arch' => 'x86_64',
      'family' => 'windows', 'skip' => 'No hosted runner (PLAT-02)'
    }
  end

  def entries
    [ubuntu, windows, skipped]
  end

  after(:each) { FileUtils.remove_entry(root) }

  def platforms(list = entries, core_list = core)
    FileUtils.mkdir_p(File.join(root, 'config'))
    File.write(File.join(root, 'config', 'platforms.yml'), YAML.dump('platforms' => list))
    File.write(File.join(root, 'config', 'core_supported_platforms.yml'), YAML.dump('core_supported' => core_list))
    described_class.load(root)
  end

  context 'when loading' do
    it 'returns entries in file order' do
      expect(platforms.entries.map(&:id)).to eq(['ubuntu-24.04-x86_64', 'windows-2025-x86_64', 'windows-2019-x86_64'])
    end

    it 'finds an entry by id' do
      expect(platforms.find('ubuntu-24.04-x86_64').image).to eq('litmusimage/ubuntu:24.04')
    end

    it 'returns nil for an unknown id' do
      expect(platforms.find('nope-1-x')).to be_nil
    end

    it 'raises when the top level key is missing' do
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config', 'platforms.yml'), YAML.dump('other' => []))
      File.write(File.join(root, 'config', 'core_supported_platforms.yml'), YAML.dump('core_supported' => []))
      expect { described_class.load(root) }.to raise_error(ArgumentError, %r{missing required key 'platforms'})
    end

    it 'lists active entries' do
      expect(platforms.active.map(&:id)).to eq(['ubuntu-24.04-x86_64', 'windows-2025-x86_64'])
    end

    it 'lists skipped entries' do
      expect(platforms.skipped.map(&:id)).to eq(['windows-2019-x86_64'])
    end
  end

  context 'with a valid config' do
    it 'reports no errors' do
      expect(platforms.errors).to eq([])
    end
  end

  context 'with schema problems' do
    def errors_for(entry, others = [])
      platforms([entry] + others).errors.join("\n")
    end

    it 'flags a duplicate id' do
      expect(errors_for(ubuntu, [ubuntu.dup])).to match(%r{duplicate id 'ubuntu-24.04-x86_64'})
    end

    it 'flags an id that does not match the id pattern' do
      expect(errors_for(ubuntu.merge('id' => 'Bad Id'))).to match(%r{Bad Id.*id})
    end

    it 'flags an id that differs from os-release-arch' do
      expect(errors_for(ubuntu.merge('id' => 'ubuntu-22.04-x86_64'))).to match(%r{must equal 'ubuntu-24.04-x86_64'})
    end

    it 'flags an unknown family' do
      expect(errors_for(ubuntu.merge('family' => 'bsd'))).to match(%r{family})
    end

    it 'flags an unknown backend' do
      expect(errors_for(ubuntu.merge('backend' => 'vm'))).to match(%r{backend})
    end

    it 'flags a container entry without an image' do
      expect(errors_for(ubuntu.except('image'))).to match(%r{image})
    end

    it 'flags an active entry without a runner' do
      expect(errors_for(windows.except('runner'))).to match(%r{runner})
    end

    it 'flags a -latest runner label' do
      expect(errors_for(windows.merge('runner' => 'windows-latest'))).to match(%r{-latest})
    end

    it 'flags a linux entry without repo_id' do
      expect(errors_for(ubuntu.except('repo_id'))).to match(%r{repo_id})
    end

    it 'flags a non-string release' do
      expect(errors_for(ubuntu.merge('release' => 24.04))).to match(%r{release.*String})
    end

    it 'flags a blank skip reason' do
      expect(errors_for(skipped.merge('skip' => '  '))).to match(%r{skip reason})
    end

    it 'exempts skip entries from backend, runner and image requirements' do
      expect(platforms([skipped]).errors).to eq([])
    end
  end

  context 'when selecting' do
    it 'returns all active entries for nil' do
      expect(platforms.select(nil).map(&:id)).to eq(['ubuntu-24.04-x86_64', 'windows-2025-x86_64'])
    end

    it 'returns all active entries for an empty list' do
      expect(platforms.select([]).size).to eq(2)
    end

    it 'returns the requested entry' do
      expect(platforms.select(['ubuntu-24.04-x86_64']).map(&:id)).to eq(['ubuntu-24.04-x86_64'])
    end

    it 'rejects a malformed id naming it' do
      expect { platforms.select(['bad id']) }.to raise_error(ArgumentError, %r{bad id})
    end

    it 'rejects an unknown id naming it' do
      expect { platforms.select(['unknown-1-x86_64']) }.to raise_error(ArgumentError, %r{unknown-1-x86_64})
    end

    it 'rejects a skipped id naming it' do
      expect { platforms.select(['windows-2019-x86_64']) }.to raise_error(ArgumentError, %r{windows-2019-x86_64})
    end

    it 'rejects an id with a trailing newline' do
      expect { platforms.select(["ubuntu-24.04-x86_64\nx"]) }.to raise_error(ArgumentError)
    end
  end

  context 'when building the matrix' do
    it 'includes id, family, runner and method for every entry' do
      row = platforms.matrix(platforms.select(['windows-2025-x86_64']))['include'].first
      expect(row).to eq(
        'id' => 'windows-2025-x86_64', 'family' => 'windows', 'runner' => 'windows-2025',
        'method' => 'runner (windows-2025)'
      )
    end

    it 'adds image and repo_id only when set' do
      row = platforms.matrix(platforms.select(['ubuntu-24.04-x86_64']))['include'].first
      expect(row).to include('image' => 'litmusimage/ubuntu:24.04', 'repo_id' => 'noble')
    end

    it 'generates single-line JSON' do
      expect(JSON.generate(platforms.matrix(platforms.active))).not_to include("\n")
    end
  end

  context 'with entry helpers' do
    it 'labels a container method' do
      expect(platforms.find('ubuntu-24.04-x86_64').method_label).to eq('container (litmusimage/ubuntu:24.04)')
    end

    it 'labels a runner method' do
      expect(platforms.find('windows-2025-x86_64').method_label).to eq('runner (windows-2025)')
    end

    it 'derives the fact filename' do
      expect(platforms.find('ubuntu-24.04-x86_64').filename).to eq('ubuntu-24.04-x86_64.facts')
    end
  end

  context 'when checking coverage' do
    it 'is empty when active or skip entries cover every triple' do
      expect(platforms.coverage_gaps).to eq([])
    end

    it 'reports a Core triple with no entry' do
      core_list = core + [{ 'os' => 'debian', 'release' => '13', 'arch' => 'aarch64' }]
      expect(platforms(entries, core_list).coverage_gaps).to eq(['debian-13-aarch64'])
    end

    it 'counts a skip entry as covering' do
      core_list = core + [{ 'os' => 'windows', 'release' => '2019', 'arch' => 'x86_64' }]
      expect(platforms(entries, core_list).coverage_gaps).to eq([])
    end
  end
end
