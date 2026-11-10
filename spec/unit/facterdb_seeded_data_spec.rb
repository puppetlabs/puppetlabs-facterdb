# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB do
  context 'with the seeded data' do
    let(:facts_root) { File.expand_path('../../facts', __dir__) }
    let(:fact_paths) { Dir.glob(File.join(facts_root, '**', '*.facts')) }

    it 'exposes every seeded file through default_fact_files' do
      expect(described_class.default_fact_files.size).to eq(fact_paths.size)
    end

    it 'seeds more than 300 files' do
      expect(fact_paths.size).to be > 300
    end

    it 'finds Debian facts for Facter 4.11' do
      facts = described_class.get_facts({ 'os.name' => 'Debian', facterversion: '/^4\.11\./' })
      expect(facts.map { |f| f[:facterversion] }).to all(start_with('4.11.'))
    end

    it 'returns at least one Debian fact set for Facter 4.11' do
      expect(described_class.get_facts({ 'os.name' => 'Debian', facterversion: '/^4\.11\./' })).not_to be_empty
    end

    it 'keys each file by the major.minor of its inner facterversion' do
      mismatches = fact_paths.reject do |path|
        version = JSON.parse(File.read(path))['facterversion'].split('.').first(2).join('.')
        File.basename(File.dirname(path)) == version
      end
      expect(mismatches).to eq([])
    end

    it 'holds no Facter 3 or 5 facts' do
      expect(described_class.get_facts([{ facterversion: %q(/^3\./) }, { facterversion: %q(/^5\./) }])).to eq([])
    end

    it 'passes the validator' do
      config = Puppetlabs::FacterDB::Tools::Config.load
      scrubber = Puppetlabs::FacterDB::Tools::Scrubber.new(config.scrub_policy)
      normaliser = Puppetlabs::FacterDB::Tools::Normaliser.new(scrubber)
      validator = Puppetlabs::FacterDB::Tools::Validator.new(config: config, scrubber: scrubber, normaliser: normaliser)
      expect(validator.validate(facts_root)).to eq([])
    end

    it 'has no filename containing a space' do
      expect(fact_paths.select { |p| File.basename(p).include?(' ') }).to eq([])
    end

    it 'has the renamed windows 2012r2 file' do
      expect(File.exist?(File.join(facts_root, '4.2', 'windows-2012r2-x86_64.facts'))).to be(true)
    end
  end
end
