# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'

# Proves upstream facterdb and perforce-facterdb coexist in one bundle.
# Every assertion runs in a fresh subprocess so state cannot leak between examples.
RSpec.describe 'facterdb and perforce-facterdb in one bundle' do # rubocop:disable RSpec/DescribeClass
  let(:root) { File.expand_path('../..', __dir__) }
  let(:fixtures) { File.join(root, 'spec', 'fixtures', 'facts') }
  let(:base_env) { ENV.to_h.reject { |k, _| k.start_with?('FACTERDB_', 'PERFORCE_FACTERDB_') } }
  let(:env) { {} }

  def run_ruby(script)
    Open3.capture3(base_env.merge(env), RbConfig.ruby, '-rbundler/setup', '-rjson', '-e', script, chdir: root)
  end

  def ruby_json(script)
    out, err, status = run_ruby(script)
    raise "subprocess failed: #{err}" unless status.success?

    JSON.parse(out)
  end

  def run_exe(exe, filter)
    out, err, status = Open3.capture3(base_env.merge(env), 'bundle', 'exec', exe, filter, chdir: root)
    raise "#{exe} failed: #{err}" unless status.success?

    JSON.parse(out)
  end

  describe 'loading' do
    it 'loads upstream first with distinct constants' do
      script = "require 'facterdb'; require 'perforce/facterdb'; puts [FacterDB.equal?(Perforce::FacterDB)].to_json"
      expect(ruby_json(script)).to eq([false])
    end

    it 'loads perforce first with distinct constants' do
      script = "require 'perforce/facterdb'; require 'facterdb'; puts [FacterDB.equal?(Perforce::FacterDB)].to_json"
      expect(ruby_json(script)).to eq([false])
    end

    it 'loads both gems from distinct specs' do
      script = "require 'facterdb'; require 'perforce/facterdb'; puts (Gem.loaded_specs.keys & %w[facterdb perforce-facterdb]).to_json"
      expect(ruby_json(script)).to contain_exactly('facterdb', 'perforce-facterdb')
    end

    it 'loads distinct facterdb.rb files' do
      script = "require 'facterdb'; require 'perforce/facterdb'; puts $LOADED_FEATURES.grep(%r{/facterdb\\.rb\\z}).to_json"
      expect(ruby_json(script).grep(%r{/perforce/facterdb\.rb\z}).size).to eq(1)
    end

    it 'loads an upstream facterdb.rb separate from the perforce one' do
      script = "require 'facterdb'; require 'perforce/facterdb'; puts $LOADED_FEATURES.grep(%r{/facterdb\\.rb\\z}).to_json"
      expect(ruby_json(script).grep_v(%r{/perforce/facterdb\.rb\z}).size).to eq(1)
    end
  end

  describe 'with a populated upstream thread cache' do
    let(:env) do
      {
        'PERFORCE_FACTERDB_SKIP_DEFAULTDB' => '1',
        'PERFORCE_FACTERDB_SEARCH_EXTERNAL_DIR' => File.join(fixtures, '4.11'),
      }
    end
    let(:facts) do
      ruby_json(<<~RUBY)
        require 'facterdb'; require 'perforce/facterdb'
        FacterDB.get_facts('os.family=RedHat')
        puts Perforce::FacterDB.get_facts('os.family=RedHat').to_json
      RUBY
    end

    it 'does not serve upstream cached results to Perforce::FacterDB' do
      expect(facts.size).to eq(1)
    end

    it 'returns Perforce fixture facts rather than the upstream array' do
      expect(facts.first['facterversion']).to start_with('4.11')
    end
  end

  describe 'with only upstream FACTERDB_* variables set' do
    let(:env) do
      {
        'FACTERDB_SKIP_DEFAULTDB' => '1',
        'FACTERDB_SEARCH_PATHS' => File.join(fixtures, '4.10'),
      }
    end
    let(:prelude) { "require 'facterdb'; require 'perforce/facterdb'; " }

    it 'changes upstream FacterDB results' do
      expect(ruby_json("#{prelude}puts [FacterDB.get_facts('facterversion=/^4\\.10/').size].to_json")).to eq([4])
    end

    it 'leaves Perforce::FacterDB external files empty' do
      expect(ruby_json("#{prelude}puts [Perforce::FacterDB.external_fact_files].to_json")).to eq([[]])
    end

    it 'leaves Perforce::FacterDB default database enabled' do
      expect(ruby_json("#{prelude}puts [Perforce::FacterDB.use_defaultdb?].to_json")).to eq([true])
    end
  end

  describe 'executables' do
    let(:env) do
      {
        'PERFORCE_FACTERDB_SKIP_DEFAULTDB' => '1',
        'PERFORCE_FACTERDB_SEARCH_EXTERNAL_DIR' => ['4.10', '4.11'].map { |v| File.join(fixtures, v) }.join(File::PATH_SEPARATOR),
      }
    end

    it 'runs perforce-facterdb against fixtures' do
      expect(run_exe('perforce-facterdb', 'os.family=RedHat').size).to eq(2)
    end

    it 'runs upstream facterdb against its default database' do
      expect(run_exe('facterdb', 'os.family=RedHat')).not_to be_empty
    end

    it 'prints an empty array from upstream facterdb for no match' do
      expect(run_exe('facterdb', 'os.family=NoSuchOS')).to eq([])
    end

    it 'prints an empty array from perforce-facterdb for no match' do
      expect(run_exe('perforce-facterdb', 'os.family=NoSuchOS')).to eq([])
    end
  end
end
