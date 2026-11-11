# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'puppetlabs/facterdb/tools'

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Puppetlabs::FacterDB::Tools::PrBody do
  let(:outcomes) do
    [
      { 'id' => 'ubuntu-24.04-x86_64', 'outcome' => 'gathered', 'method' => 'container (litmusimage/ubuntu:24.04)', 'action' => 'added', 'reason' => '' },
      { 'id' => 'debian-12-x86_64', 'outcome' => 'failed', 'method' => 'runner (x)', 'reason' => "bad | pipe\nnewline" },
      { 'id' => 'aix-7.2-power', 'outcome' => 'skipped', 'method' => 'runner (y)', 'reason' => 'no package' },
    ]
  end
  let(:status) { "?? facts/4.23/ubuntu-24.04-x86_64.facts\n M facts/4.23/debian-12-x86_64.facts\n M config/facter_versions.yml\n" }
  let(:body) do
    described_class.render(version: '4.23.0', agent: '9.1.3', outcomes: outcomes, git_status: status, run_url: 'https://example.com/run/1')
  end

  it 'renders a sorted table with one row per outcome' do
    expect(body).to include('| Platform | Outcome | Method | Detail |')
    rows = body.lines.grep(%r{\A\| (ubuntu|debian|aix)}).map { |l| l[%r{\A\| (\S+)}, 1] }
    expect(rows).to eq(['aix-7.2-power', 'debian-12-x86_64', 'ubuntu-24.04-x86_64'])
  end

  it 'lists added and changed fact files only' do
    expect(body).to match(%r{Added:\n- `facts/4.23/ubuntu-24.04-x86_64.facts`})
    expect(body).to match(%r{Changed:\n- `facts/4.23/debian-12-x86_64.facts`})
    expect(body).not_to include('config/facter_versions.yml')
  end

  it 'says None when there are no changes' do
    empty = described_class.render(version: '4.23.0', agent: '9.1.3', outcomes: [], git_status: '', run_url: 'u')
    expect(empty).to include("Added:\nNone", "Changed:\nNone")
  end

  it 'includes validation line, run url, versions, CI note and review line' do
    expect(body).to include('rake facts:normalise` and `rake facts:validate` passed', 'https://example.com/run/1', '4.23.0', '9.1.3')
    expect(body).to include('Close and reopen this PR', 'first generated file per OS')
  end

  it 'escapes pipes and flattens newlines in reasons' do
    row = body.lines.find { |l| l.start_with?('| debian-12') }
    expect(row).to include('bad \\| pipe newline')
    expect(row.count("\n")).to eq(1)
  end

  describe 'gather:update_map' do
    let(:dir) { Dir.mktmpdir }
    let(:copy) { File.join(dir, 'facter_versions.yml') }

    after(:each) { FileUtils.remove_entry(dir) }

    def run_task(version, major, agent)
      env = { 'FACTER_VERSIONS_PATH' => copy, 'FACTER_VERSION' => version, 'AGENT_MAJOR' => major, 'AGENT_VERSION' => agent }
      Open3.capture2e(env, 'bundle', 'exec', 'rake', 'gather:update_map', chdir: Puppetlabs::FacterDB::Tools::REPO_ROOT)
    end

    it 'is idempotent and writes new entries once' do
      FileUtils.cp(File.join(Puppetlabs::FacterDB::Tools::REPO_ROOT, 'config', 'facter_versions.yml'), copy)
      original = File.binread(copy)
      out, status = run_task('4.12.0', '8', '8.12.0')
      expect([status.success?, out.strip]).to eq([true, 'unchanged'])
      expect(File.binread(copy)).to eq(original)

      out, = run_task('4.99.0', '9', '9.99.0')
      expect(out.strip).to eq('updated')
      expect(File.read(copy)).to include("'4.99.0':")
      out, = run_task('4.99.0', '9', '9.99.0')
      expect(out.strip).to eq('unchanged')
    end

    it 'aborts on malformed input' do
      FileUtils.cp(File.join(Puppetlabs::FacterDB::Tools::REPO_ROOT, 'config', 'facter_versions.yml'), copy)
      _out, status = run_task('4.x', '9', '9.1.3')
      expect(status.success?).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
