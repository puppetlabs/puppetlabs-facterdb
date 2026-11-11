# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::FacterVersions, :aggregate_failures do
  let(:root) { Dir.mktmpdir }
  let(:map_path) { File.join(root, 'facter_versions.yml') }
  let(:facts_root) { File.join(root, 'facts') }

  after(:each) { FileUtils.remove_entry(root) }

  def put_map(content)
    File.write(map_path, content)
  end

  def put_fact(rel, version)
    path = File.join(facts_root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate('facterversion' => version))
  end

  def map_with(*versions)
    map = described_class.new(map_path)
    versions.each { |v| map.add(v, '8.12.0') }
    map
  end

  describe '.load' do
    it 'treats a comments-only empty map as empty' do
      put_map("# comment\n{}\n")
      expect(described_class.load(map_path).entries).to eq({})
    end

    it 'loads entries as a version to agent map' do
      put_map("'4.12.0': { agent: '8.12.0' }\n")
      expect(described_class.load(map_path).entries).to eq('4.12.0' => '8.12.0')
    end

    it 'loads the checked-in map' do
      expect(described_class.load.entries).to be_a(Hash)
    end

    [
      "'4.12': { agent: '8.12.0' }\n",
      "'4.12.0': {}\n",
      "'4.12.0': { agent: '8.12' }\n",
    ].each do |content|
      it "rejects #{content.inspect} naming the file" do
        put_map(content)
        expect { described_class.load(map_path) }.to raise_error(ArgumentError, %r{#{Regexp.escape(map_path)}})
      end
    end
  end

  describe '#render' do
    it 'sorts by Gem::Version and round-trips' do
      map = map_with('4.12.0', '4.9.0', '4.13.0')
      lines = map.render.lines.reject { |l| l.start_with?('#') }
      expect(lines.map { |l| l[%r{\d+\.\d+\.\d+}] }).to eq(['4.9.0', '4.12.0', '4.13.0'])
      put_map(map.render)
      expect(described_class.load(map_path).entries).to eq(map.entries)
    end

    it 'renders an empty map as {}' do
      expect(described_class.new(map_path).render).to end_with("{}\n")
    end
  end

  describe '.stored_version' do
    it 'is nil when the directory is missing or empty' do
      expect(described_class.stored_version(facts_root, '4.12')).to be_nil
      FileUtils.mkdir_p(File.join(facts_root, '4.12'))
      expect(described_class.stored_version(facts_root, '4.12')).to be_nil
    end

    it 'returns the max facterversion' do
      put_fact('4.12/a.facts', '4.12.0')
      put_fact('4.12/b.facts', '4.12.10')
      put_fact('4.12/c.facts', '4.12.9')
      expect(described_class.stored_version(facts_root, '4.12')).to eq(Gem::Version.new('4.12.10'))
    end

    it 'withholds details on invalid JSON' do
      FileUtils.mkdir_p(File.join(facts_root, '4.12'))
      File.write(File.join(facts_root, '4.12', 'bad.facts'), '{ "secret": ')
      expect { described_class.stored_version(facts_root, '4.12') }.to raise_error(ArgumentError, %r{details withheld}) { |e| expect(e.message).not_to include('secret') }
    end
  end

  describe '#missing' do
    let(:map) { map_with('4.12.0', '4.12.1', '4.13.0') }

    it 'treats versions covered by a newer stored file as gathered' do
      put_fact('4.12/a.facts', '4.12.1')
      expect(map.missing(facts_root)).to eq(['4.13.0'])
    end

    it 'flags later patch versions when only an older one is stored' do
      put_fact('4.12/a.facts', '4.12.0')
      put_fact('4.13/a.facts', '4.13.0')
      expect(map.missing(facts_root)).to eq(['4.12.1'])
    end

    it 'flags everything when nothing is stored' do
      expect(map.missing(facts_root)).to eq(['4.12.0', '4.12.1', '4.13.0'])
    end
  end

  describe '#resolve' do
    let(:map) { map_with('4.12.0', '4.13.0') }

    it 'returns the oldest missing version for empty input' do
      expect(map.resolve('', facts_root)).to eq('4.12.0')
    end

    it 'returns nil when nothing is missing' do
      put_fact('4.12/a.facts', '4.12.0')
      put_fact('4.13/a.facts', '4.13.0')
      expect(map.resolve('', facts_root)).to be_nil
    end

    it 'returns an explicit version even when already gathered' do
      put_fact('4.13/a.facts', '4.13.0')
      expect(map.resolve('4.13.0', facts_root)).to eq('4.13.0')
    end

    it 'rejects a version not in the map' do
      expect { map.resolve('4.99.0', facts_root) }.to raise_error(ArgumentError)
    end

    ['4.13', "4.13.0\n::set-output"].each do |input|
      it "rejects #{input.inspect} without echoing it" do
        expect { map.resolve(input, facts_root) }.to raise_error(ArgumentError) { |e| expect(e.message).not_to include(input.strip) }
      end
    end
  end

  describe '.collection_for' do
    it 'derives the puppetcore collection from the agent major' do
      expect(described_class.collection_for('9.1.3')).to eq('puppetcore9')
      expect(described_class.collection_for('8.12.0')).to eq('puppetcore8')
    end
  end
end
