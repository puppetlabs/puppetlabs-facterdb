# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::Gather, :aggregate_failures do
  let(:src) { Dir.mktmpdir }
  let(:dest) { Dir.mktmpdir }

  after(:each) do
    FileUtils.remove_entry(src)
    FileUtils.remove_entry(dest)
  end

  def facts(name: 'Debian', major: '12', hardware: 'x86_64', version: '4.12.0')
    { 'facterversion' => version, 'os' => { 'name' => name, 'release' => { 'major' => major }, 'hardware' => hardware } }
  end

  def put(root, rel, content)
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content.is_a?(String) ? content : JSON.generate(content))
  end

  def stored_version(rel)
    JSON.parse(File.read(File.join(dest, rel)))['facterversion']
  end

  describe '.relative_path_for' do
    it 'names a Debian file' do
      expect(described_class.relative_path_for(facts)).to eq('4.12/debian-12-x86_64.facts')
    end

    it 'normalises x64 to x86_64' do
      expect(described_class.relative_path_for(facts(name: 'windows', major: '2022', hardware: 'x64'))).to eq('4.12/windows-2022-x86_64.facts')
    end

    it 'keeps dotted releases and aarch64' do
      expect(described_class.relative_path_for(facts(name: 'Ubuntu', major: '22.04', hardware: 'aarch64'))).to eq('4.12/ubuntu-22.04-aarch64.facts')
    end

    it 'normalises arm64 to aarch64' do
      expect(described_class.relative_path_for(facts(hardware: 'arm64'))).to eq('4.12/debian-12-aarch64.facts')
    end

    it 'rejects a path-traversing os name without echoing it' do
      expect { described_class.relative_path_for(facts(name: '../x')) }.to raise_error(ArgumentError) { |e| expect(e.message).not_to include('../x') }
    end

    it 'rejects a missing release major' do
      data = facts
      data['os']['release'] = {}
      expect { described_class.relative_path_for(data) }.to raise_error(ArgumentError, %r{os\.release\.major})
    end

    it 'rejects a malformed facterversion' do
      expect { described_class.relative_path_for(facts(version: 'abc')) }.to raise_error(ArgumentError, %r{facterversion})
    end
  end

  describe '.place' do
    it 'writes a new file derived from content, not the source name' do
      put(src, 'facts-Debian-12/whatever.facts', facts)
      result = described_class.place(src, dest, '4.12.0')
      expect(result.placed).to eq(['4.12/debian-12-x86_64.facts'])
      expect(File.exist?(File.join(dest, '4.12/debian-12-x86_64.facts'))).to be(true)
    end

    it 'replaces an older stored patch' do
      put(dest, '4.12/debian-12-x86_64.facts', facts(version: '4.12.0'))
      put(src, 'a/x.facts', facts(version: '4.12.1'))
      result = described_class.place(src, dest, '4.12.1')
      expect(result.placed).to eq(['4.12/debian-12-x86_64.facts'])
      expect(stored_version('4.12/debian-12-x86_64.facts')).to eq('4.12.1')
    end

    it 'skips and reports when a newer patch is stored' do
      put(dest, '4.12/debian-12-x86_64.facts', facts(version: '4.12.2'))
      put(src, 'a/x.facts', facts(version: '4.12.1'))
      result = described_class.place(src, dest, '4.12.1')
      expect([result.skipped, result.placed]).to eq([['4.12/debian-12-x86_64.facts'], []])
      expect(stored_version('4.12/debian-12-x86_64.facts')).to eq('4.12.2')
    end

    it 'never removes existing files' do
      put(dest, '4.11/debian-11-x86_64.facts', facts(major: '11', version: '4.11.0'))
      put(src, 'a/x.facts', facts)
      described_class.place(src, dest, '4.12.0')
      expect(File.exist?(File.join(dest, '4.11/debian-11-x86_64.facts'))).to be(true)
    end

    it 'reports a facterversion mismatch as invalid' do
      put(src, 'a/x.facts', facts(version: '4.12.1'))
      result = described_class.place(src, dest, '4.12.0')
      expect(result.invalid).to eq(['a/x.facts'])
      expect(result.placed).to eq([])
    end

    it 'reports invalid JSON as invalid' do
      put(src, 'a/x.facts', '{not json')
      expect(described_class.place(src, dest, '4.12.0').invalid).to eq(['a/x.facts'])
    end

    it 'reports an unnameable file as invalid' do
      put(src, 'a/x.facts', facts(name: '../x'))
      expect(described_class.place(src, dest, '4.12.0').invalid).to eq(['a/x.facts'])
    end
  end

  describe '.summary' do
    def summary(succeeded)
      described_class.summary(
        labels: ['Debian-12', 'Windows-2022'], succeeded: succeeded, version: '4.12.0', agent: '8.12.0',
        placed: ['4.12/debian-12-x86_64.facts'], skipped: ['4.12/ubuntu-22.04-x86_64.facts']
      )
    end

    it 'lists failed legs and says the run stays red' do
      body, failed = summary(['Debian-12'])
      expect(failed).to eq(['Windows-2022'])
      expect(body).to include('4.12.0', '8.12.0', 'Debian-12', 'Windows-2022', '4.12/ubuntu-22.04-x86_64.facts', 'stays red')
    end

    it 'reports no failures when every leg succeeded' do
      _, failed = summary(['Debian-12', 'Windows-2022'])
      expect(failed).to eq([])
    end
  end
end
