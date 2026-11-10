# frozen_string_literal: true

require 'spec_helper'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::Normaliser do
  let(:config) { Puppetlabs::FacterDB::Tools::Config.load }
  let(:scrubber) { Puppetlabs::FacterDB::Tools::Scrubber.new(config.scrub_policy) }

  describe '.format' do
    it 'sorts keys recursively, keeps array order and indents by two spaces' do
      out = described_class.format('b' => { 'z' => 1, 'a' => [3, 1, 2] }, 'a' => 0)
      expect(out).to eq("{\n  \"a\": 0,\n  \"b\": {\n    \"a\": [\n      3,\n      1,\n      2\n    ],\n    \"z\": 1\n  }\n}\n")
    end

    it 'renders empty arrays and hashes compactly on every Ruby' do
      out = described_class.format('a' => [], 'b' => {}, 'c' => [[]])
      expect(out).to eq("{\n  \"a\": [],\n  \"b\": {},\n  \"c\": [\n    []\n  ]\n}\n")
    end

    it 'ends with exactly one newline' do
      expect(described_class.format('a' => 1)).to match(%r{[^\n]\n\z})
    end

    it 'is stable for every fixture file' do
      Dir.glob('**/*.facts', base: fixtures_dir).each do |name|
        once = described_class.format(JSON.parse(File.read(File.join(fixtures_dir, name))))
        expect(described_class.format(JSON.parse(once))).to eq(once), name
      end
    end
  end

  describe '#render' do
    it 'equals format of the scrubbed data' do
      data = { 'system_uptime' => { 'seconds' => 5 }, 'b' => 1, 'a' => 2 }
      expect(described_class.new(scrubber).render(data)).to eq(described_class.format(scrubber.scrub(data)))
    end

    it 'is stable under a second pass' do
      data = JSON.parse(File.read(File.join(fixtures_dir, '4.11', 'debian-12-x86_64.facts')))
      normaliser = described_class.new(scrubber)
      once = normaliser.render(data)
      expect(normaliser.render(JSON.parse(once))).to eq(once)
    end
  end
end
