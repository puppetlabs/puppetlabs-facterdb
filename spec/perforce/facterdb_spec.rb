# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Perforce::FacterDB do
  let(:older_dir) { File.join(fixtures_dir, '4.10') }
  let(:newer_dir) { File.join(fixtures_dir, '4.11') }
  let(:both_dirs) { [older_dir, newer_dir].join(File::PATH_SEPARATOR) }

  def filenames(facts)
    facts.map { |f| f[:_facterdb_filename] }
  end

  context 'with fixture directories and the default database skipped' do
    before(:each) do
      ENV['PERFORCE_FACTERDB_SKIP_DEFAULTDB'] = '1'
      ENV['PERFORCE_FACTERDB_SEARCH_EXTERNAL_DIR'] = both_dirs
    end

    describe '.get_facts' do
      it 'matches a Hash filter on a nested path' do
        expect(described_class.get_facts({ 'os.family' => 'Debian' }).size).to eq(4)
      end

      it 'returns an empty Array when nothing matches' do
        expect(described_class.get_facts({ 'os.family' => 'NoSuchOS' })).to eq([])
      end

      it 'combines Hash keys with and' do
        expect(described_class.get_facts({ 'os.family' => 'Debian', facterversion: '4.11.0' }).size).to eq(2)
      end

      it 'treats an Array of Hashes as or' do
        expect(described_class.get_facts([{ 'os.family' => 'RedHat' }, { 'os.family' => 'windows' }]).size).to eq(3)
      end

      it 'accepts a String filter with a nested path and a regex' do
        facts = described_class.get_facts('os.family=RedHat and facterversion=/^4\.11/')
        expect(facts.map { |f| f[:facterversion] }).to eq(['4.11.0'])
      end

      it 'returns only the RedHat 4.11 factset for the String filter' do
        facts = described_class.get_facts('os.family=RedHat and facterversion=/^4\.11/')
        expect(facts.map { |f| f[:os]['family'] }).to eq(['RedHat'])
      end

      it 'matches facterversion against the inner fact' do
        expect(described_class.get_facts({ facterversion: '4.10.0' }).size).to eq(4)
      end

      it 'matches a facterversion regex' do
        expect(described_class.get_facts({ facterversion: '/^4\.11/' }).size).to eq(3)
      end

      it 'returns every factset for a nil filter' do
        expect(described_class.get_facts(nil).size).to eq(7)
      end

      it 'symbolizes top-level keys by default' do
        expect(described_class.get_facts({ 'os.family' => 'windows' }).first.keys).to all(be_a(Symbol))
      end

      it 'keeps String keys with symbolize_keys: false' do
        expect(described_class.get_facts({ 'os.family' => 'windows' }, symbolize_keys: false).first.keys).to all(be_a(String))
      end

      it 'returns the cached object for a repeated filter' do
        filter = { 'os.family' => 'Debian' }
        expect(described_class.get_facts(filter)).to equal(described_class.get_facts(filter))
      end

      it 'stores the cache under perforce_facterdb thread keys' do
        described_class.get_facts({ 'os.family' => 'Debian' })
        expect(Thread.current[:perforce_facterdb_last_filter_seen]).to eq({ 'os.family' => 'Debian' })
      end

      it 'never writes the upstream facterdb thread keys' do
        described_class.get_facts({ 'os.family' => 'Debian' })
        expect(Thread.current[:facterdb_last_filter_seen]).to be_nil
      end

      it 'clears the thread cache on cleanup' do
        described_class.get_facts({ 'os.family' => 'Debian' })
        described_class.cleanup
        expect(Thread.current[:perforce_facterdb_last_facts_seen]).to be_nil
      end
    end

    describe '.external_fact_files' do
      it 'finds fact files in every directory of the search path' do
        expect(described_class.external_fact_files).to include(a_string_ending_with('4.10/windows-2022-x86_64.facts'), a_string_ending_with('4.11/ubuntu-24.04-x86_64.facts'))
      end

      it 'finds all seven fixtures' do
        expect(described_class.external_fact_files.size).to eq(7)
      end
    end

    describe '.facterdb_fact_files' do
      it 'lists external files with no default files' do
        expect(described_class.facterdb_fact_files.size).to eq(7)
      end
    end
  end

  describe '.external_fact_files' do
    it 'returns an empty Array for nil' do
      expect(described_class.external_fact_files(nil)).to eq([])
    end

    it 'returns an empty Array for an empty String' do
      expect(described_class.external_fact_files('')).to eq([])
    end

    it 'skips a nonexistent directory without output' do
      expect { described_class.external_fact_files('/no/such/dir') }.not_to output.to_stderr
    end

    it 'returns no files for a nonexistent directory' do
      expect(described_class.external_fact_files('/no/such/dir')).to eq([])
    end

    it 'still finds files in valid directories next to a nonexistent one' do
      expect(described_class.external_fact_files(['/no/such/dir', newer_dir].join(File::PATH_SEPARATOR)).size).to eq(3)
    end
  end

  describe '.use_defaultdb?' do
    it 'is true when PERFORCE_FACTERDB_SKIP_DEFAULTDB is unset' do
      expect(described_class.use_defaultdb?).to be(true)
    end

    it 'is false when PERFORCE_FACTERDB_SKIP_DEFAULTDB is set' do
      ENV['PERFORCE_FACTERDB_SKIP_DEFAULTDB'] = '1'
      expect(described_class.use_defaultdb?).to be(false)
    end

    it 'is false when PERFORCE_FACTERDB_SKIP_DEFAULTDB is set to an empty string' do
      ENV['PERFORCE_FACTERDB_SKIP_DEFAULTDB'] = ''
      expect(described_class.use_defaultdb?).to be(false)
    end
  end

  describe '.inject_source?' do
    it 'is false by default' do
      expect(described_class.inject_source?).to be(false)
    end

    it 'is true when PERFORCE_FACTERDB_INJECT_SOURCE is set' do
      ENV['PERFORCE_FACTERDB_INJECT_SOURCE'] = '1'
      expect(described_class.inject_source?).to be(true)
    end
  end

  context 'with only the upstream FACTERDB_* variables set' do
    before(:each) do
      ENV['FACTERDB_SEARCH_PATHS'] = both_dirs
      ENV['FACTERDB_SKIP_DEFAULTDB'] = '1'
      ENV['FACTERDB_INJECT_SOURCE'] = '1'
    end

    it 'ignores FACTERDB_SEARCH_PATHS' do
      expect(described_class.external_fact_files).to eq([])
    end

    it 'ignores FACTERDB_SKIP_DEFAULTDB' do
      expect(described_class.use_defaultdb?).to be(true)
    end

    it 'ignores FACTERDB_INJECT_SOURCE' do
      expect(described_class.inject_source?).to be(false)
    end
  end

  context 'with the default database skipped and no external directory' do
    before(:each) { ENV['PERFORCE_FACTERDB_SKIP_DEFAULTDB'] = '1' }

    it 'returns an empty result without raising' do
      expect(described_class.get_facts({ 'os.family' => 'Debian' })).to eq([])
    end
  end

  describe '.default_fact_files' do
    it 'globs the gem facts directory' do
      expect(described_class.default_fact_files).to all(start_with(File.expand_path('../../facts', __dir__)))
    end

    it 'returns nothing when the default database is skipped' do
      ENV['PERFORCE_FACTERDB_SKIP_DEFAULTDB'] = '1'
      expect(described_class.default_fact_files).to eq([])
    end
  end

  context 'with PERFORCE_FACTERDB_INJECT_SOURCE set' do
    before(:each) do
      ENV['PERFORCE_FACTERDB_SKIP_DEFAULTDB'] = '1'
      ENV['PERFORCE_FACTERDB_SEARCH_EXTERNAL_DIR'] = older_dir
      ENV['PERFORCE_FACTERDB_INJECT_SOURCE'] = '1'
    end

    it 'injects the source file name' do
      expect(filenames(described_class.get_facts({ 'os.family' => 'windows' }))).to eq(['windows-2022-x86_64.facts'])
    end

    it 'injects the source file path' do
      expect(described_class.get_facts({ 'os.family' => 'windows' }).first[:_facterdb_path]).to eq(File.join(older_dir, 'windows-2022-x86_64.facts'))
    end
  end

  describe '.generate_filter_str' do
    it 'joins a Hash with and' do
      expect(described_class.generate_filter_str({ 'a' => 1, 'b' => 2 })).to eq('a=1 and b=2')
    end

    it 'joins an Array of Hashes with or' do
      expect(described_class.generate_filter_str([{ 'a' => 1, 'b' => 2 }, { 'c' => 3 }])).to eq('(a=1 and b=2) or (c=3)')
    end

    it 'passes a String through' do
      expect(described_class.generate_filter_str('a=1')).to eq('a=1')
    end

    it 'returns an empty String for nil' do
      expect(described_class.generate_filter_str(nil)).to eq('')
    end

    it 'raises InvalidFilter for anything else' do
      expect { described_class.generate_filter_str(1) }.to raise_error(Perforce::FacterDB::Errors::InvalidFilter, %r{received Integer})
    end
  end

  describe '.valid_filters?' do
    it 'is true for a valid filter' do
      expect(described_class.valid_filters?('foo')).to be(true)
    end

    it 'is false for an invalid filter' do
      expect(described_class.valid_filters?('and')).to be(false)
    end
  end

  describe 'namespace isolation' do
    it 'does not define a top-level FacterDB constant' do
      expect(Object.const_defined?(:FacterDB)).to be(false)
    end

    it 'exposes the version constant' do
      expect(Perforce::FacterDB::Version::STRING).to eq('0.1.0')
    end
  end
end
