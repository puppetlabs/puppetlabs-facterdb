# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::VersionMap do
  let(:path) { File.join(Dir.mktmpdir, 'facter_versions.yml') }
  let(:data) { { '4.23.0' => { '8' => '8.22.2', '9' => '9.1.3' }, '4.20.0' => { '8' => '8.20.0' } } }
  let(:map) { described_class.new(path, 'versions' => data) }

  describe '#resolve' do
    it 'returns the newest agent major' do
      expect(map.resolve('4.23.0')).to eq(described_class::Resolution.new(facter: '4.23.0', agent_major: '9', agent: '9.1.3'))
    end

    it 'returns the only agent major when there is one' do
      expect(map.resolve('4.20.0').agent_major).to eq('8')
    end

    it 'raises UnknownVersion for an absent version' do
      expect { map.resolve('4.99.0') }.to raise_error(described_class::UnknownVersion)
    end

    it 'compares agent majors numerically' do
      big = described_class.new(path, 'versions' => { '4.30.0' => { '9' => '9.1.0', '10' => '10.0.0' } })
      expect(big.resolve('4.30.0').agent_major).to eq('10')
    end
  end

  describe '#add' do
    it 'adds a new version and reports the change' do
      expect(map.add('4.24.0', '9' => '9.2.0')).to be(true)
    end

    it 'makes the version known' do
      map.add('4.24.0', '9' => '9.2.0')
      expect(map.include?('4.24.0')).to be(true)
    end

    it 'is idempotent' do
      map.add('4.24.0', '9' => '9.2.0')
      expect(map.add('4.24.0', '9' => '9.2.0')).to be(false)
    end

    it 'replaces a different agent for an existing version' do
      map.add('4.23.0', '9' => '9.1.4')
      expect(map.resolve('4.23.0').agent).to eq('9.1.4')
    end

    it 'rejects a malformed Facter version' do
      expect { map.add('4.24', '9' => '9.2.0') }.to raise_error(ArgumentError)
    end

    it 'rejects a malformed agent version' do
      expect { map.add('4.24.0', '9' => 'x') }.to raise_error(ArgumentError)
    end

    it 'rejects a malformed agent major' do
      expect { map.add('4.24.0', 'nine' => '9.2.0') }.to raise_error(ArgumentError)
    end

    it 'rejects an empty agent set' do
      expect { map.add('4.24.0', {}) }.to raise_error(ArgumentError)
    end
  end

  describe '#versions' do
    it 'sorts by Gem::Version' do
      small = described_class.new(path, 'versions' => { '4.12.0' => { '8' => '8.12.0' }, '4.9.0' => { '8' => '8.9.0' } })
      expect(small.versions).to eq(['4.9.0', '4.12.0'])
    end
  end

  describe '#dump and .load' do
    it 'round-trips through a file' do
      map.write(path)
      expect(described_class.load(path).dump).to eq(map.dump)
    end

    it 'quotes keys and values and sorts versions' do
      expect(map.dump).to match(%r{^  '4\.20\.0':\n    '8': '8\.20\.0'\n  '4\.23\.0':\n    '8': '8\.22\.2'\n    '9': '9\.1\.3'\n\z})
    end

    it 'keeps the header comment' do
      expect(map.dump).to start_with('# ')
    end

    it 'raises when the versions key is missing' do
      File.write(path, "other: 1\n")
      expect { described_class.load(path) }.to raise_error(ArgumentError, %r{#{Regexp.escape(path)}})
    end
  end
end
