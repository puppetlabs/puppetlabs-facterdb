# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'puppetlabs/facterdb/bin'

RSpec.describe Puppetlabs::FacterDB::Bin do
  let(:both_dirs) { ['4.10', '4.11'].map { |v| File.join(fixtures_dir, v) }.join(File::PATH_SEPARATOR) }
  let(:repo_root) { File.expand_path('../../..', __dir__) }

  def run_in_process(args)
    JSON.parse(capture_stdout { described_class.new(args).run })
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def run_subprocess(*filter_args)
    env = {
      'PUPPETLABS_FACTERDB_SKIP_DEFAULTDB' => '1',
      'PUPPETLABS_FACTERDB_SEARCH_EXTERNAL_DIR' => both_dirs,
    }
    Open3.capture3(env, RbConfig.ruby, '-Ilib', 'exe/puppetlabs-facterdb', *filter_args, chdir: repo_root)
  end

  context 'with fixture directories and the default database skipped' do
    before(:each) do
      ENV['PUPPETLABS_FACTERDB_SKIP_DEFAULTDB'] = '1'
      ENV['PUPPETLABS_FACTERDB_SEARCH_EXTERNAL_DIR'] = both_dirs
    end

    describe '#run' do
      it 'prints a JSON array of matching facts' do
        expect(run_in_process(['os.family=Debian']).size).to eq(4)
      end

      it 'matches the lowercase windows family value' do
        expect(run_in_process(['os.family=windows']).size).to eq(1)
      end

      it 'prints [] when nothing matches' do
        expect(capture_stdout { described_class.new(['os.family=NoSuchOS']).run }.strip).to eq('[]')
      end

      it 'prints all facts when no filter is given' do
        expect(run_in_process([]).size).to eq(7)
      end
    end
  end

  describe 'exe/puppetlabs-facterdb' do
    it 'exits 0 and prints one matching fact' do
      stdout, _stderr, status = run_subprocess('os.family=RedHat and facterversion=/^4\.11/')
      expect([status.exitstatus, JSON.parse(stdout).size]).to eq([0, 1])
    end

    it 'exits 0 and prints [] when nothing matches' do
      stdout, _stderr, status = run_subprocess('os.family=NoSuchOS')
      expect([status.exitstatus, stdout.strip]).to eq([0, '[]'])
    end

    it 'joins an unquoted multi-word filter instead of dropping words' do
      stdout, _stderr, status = run_subprocess('os.family=RedHat', 'and', 'facterversion=/^4\.11/')
      expect([status.exitstatus, JSON.parse(stdout).size]).to eq([0, 1])
    end

    it 'exits 1 with a one-line message for an invalid filter' do
      stdout, stderr, status = run_subprocess('and')
      expect([status.exitstatus, stdout, stderr.lines.size, stderr]).to match([1, '', 1, a_string_starting_with('puppetlabs-facterdb: ')])
    end
  end
end
