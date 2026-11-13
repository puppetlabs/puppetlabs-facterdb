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

  describe '.run_command' do
    let(:runner_class) do
      Struct.new(:result, :calls) do
        def run_shell(*args, **opts)
          calls << [args, opts]
          result
        end
      end
    end
    let(:runner) { runner_class.new(Struct.new(:stdout, :stderr, :exit_code).new('out-marker', 'err-marker', exit_code), []) }
    let(:exit_code) { 0 }

    it 'returns stdout and opts out of litmus raising on failure' do
      expect(described_class.run_command(runner, 'facter -j')).to eq('out-marker')
      expect(runner.calls).to eq([[['facter -j'], { expect_failures: true }]])
    end

    context 'when the command exits nonzero' do
      let(:exit_code) { 3 }

      it 'raises a value-free error naming the command and exit code' do
        expect { described_class.run_command(runner, 'facter -j') }.to raise_error(described_class::CommandError) { |e|
          expect(e.message).to eq('facter -j failed with exit code 3 (details withheld)')
          expect(e.message).not_to match(%r{out-marker|err-marker})
        }
      end
    end

    context 'when the exit code is missing' do
      let(:exit_code) { nil }

      it 'treats it as a failure' do
        expect { described_class.run_command(runner, 'facter -j') }.to raise_error(described_class::CommandError, %r{nil})
      end
    end
  end

  describe '.render_scrubbed' do
    let(:raw) do
      facts.merge(
        'networking' => { 'hostname' => 'secret-host', 'fqdn' => 'secret-host.corp.example' },
        'ec2_userdata' => 'password=hunter2',
        'gce' => { 'instance' => { 'id' => 42 } },
        'zeta' => 1,
        'alpha' => 2,
      )
    end

    it 'replaces leaf values on scrub paths and drops raw values' do
      output = described_class.render_scrubbed(raw)
      parsed = JSON.parse(output)
      expect(parsed.values_at('ec2_userdata', 'gce')).to eq(['', {}])
      expect(parsed['networking']).to eq('hostname' => 'foo', 'fqdn' => 'foo.example.com')
      expect(output).not_to match(%r{secret-host|hunter2})
    end

    it 'returns the normalised form' do
      output = described_class.render_scrubbed(raw)
      expect(output).to end_with("}\n")
      expect(output.index('"alpha"')).to be < output.index('"zeta"')
    end

    it 'is idempotent' do
      once = described_class.render_scrubbed(raw)
      expect(described_class.render_scrubbed(JSON.parse(once))).to eq(once)
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

  describe '.classify_failure' do
    {
      'No match for argument: puppet-agent-8.12.0' => :agent_unavailable,
      'Package puppet-agent is not available, but is referred to by another package' => :agent_unavailable,
      'Unable to retrieve a valid package for puppet-agent' => :agent_unavailable,
      'curl: ERROR 404: Not Found' => :agent_unavailable,
      'provisioning of debian-13 failed.' => :provision_failed,
      'provision service returned an error (HTTP 500)' => :provision_failed,
      'ssh: connect to host 10.1.2.3 port 22: Connection refused' => :other,
      '' => :other,
    }.each do |message, category|
      it "classifies #{message.inspect} as #{category}" do
        expect(described_class.classify_failure(message)).to eq(category)
      end
    end

    it 'returns only a symbol and treats nil as other' do
      expect(described_class.classify_failure('No match for argument: puppet-agent-8.12.0 at 10.9.8.7')).to be_a(Symbol)
      expect(described_class.classify_failure(nil)).to eq(:other)
    end
  end

  describe '.write_result and .read_results' do
    def write_leg(label, status, reason = nil)
      described_class.write_result(File.join(src, "result-#{label}"), label, status, reason)
    end

    let(:results) { described_class.read_results(src, ['A', 'B', 'C', 'D', 'E']) }

    before(:each) do
      write_leg('A', 'success')
      write_leg('B', 'skipped', :agent_unavailable)
      put(src, 'result-D/result.json', '{not json')
      put(src, 'result-E/result.json', '{"status":"bogus"}')
    end

    it 'round-trips each status and treats a missing or invalid result as failed' do
      expect(results.transform_values { |r| r['status'] }.values).to eq(['success', 'skipped', 'failed', 'failed', 'failed'])
      expect(results.values_at('B', 'C').map { |r| r['reason'] }).to eq(['agent_unavailable', 'no_result'])
    end

    it 'records the label, status and reason as JSON' do
      write_leg('A', 'failed', :provision_failed)
      expect(JSON.parse(File.read(File.join(src, 'result-A', 'result.json')))).to eq('label' => 'A', 'status' => 'failed', 'reason' => 'provision_failed')
    end

    it 'rejects an unknown status' do
      expect { write_leg('A', 'weird') }.to raise_error(ArgumentError)
    end
  end

  describe '.summary' do
    let(:labels) { ['Debian-12', 'Debian-13', 'Windows-2022', 'Ubuntu-24.04'] }
    let(:results) do
      {
        'Debian-12' => { 'status' => 'success', 'reason' => nil },
        'Debian-13' => { 'status' => 'skipped', 'reason' => 'agent_unavailable' },
        'Windows-2022' => { 'status' => 'failed', 'reason' => 'provision_failed' },
      }
    end

    def summary(results)
      described_class.summary(
        labels: labels, results: results, version: '4.12.0', agent: '8.12.0',
        placed: ['4.12/debian-12-x86_64.facts'], skipped: ['4.12/ubuntu-22.04-x86_64.facts']
      )
    end

    it 'lists succeeded, skipped and failed legs with reasons and says the run stays red' do
      body, failed = summary(results)
      expect(failed).to eq(['Windows-2022', 'Ubuntu-24.04'])
      expect(body).to include('- Debian-12', '## Skipped (no agent package for this OS)', '- Debian-13: no agent package for this OS')
      expect(body).to include('- Windows-2022: provision service error', '- Ubuntu-24.04: no result recorded', 'stays red')
      expect(body).to include('4.12/debian-12-x86_64.facts', '4.12/ubuntu-22.04-x86_64.facts')
    end

    it 'states the versions and links the release notes' do
      body, = summary(results)
      expect(body).to include('Facter 4.12.0', 'agent 8.12.0', Puppetlabs::FacterDB::Tools::ReleaseNotes::URL)
    end

    it 'does not fail the run when legs are only skipped or succeeded' do
      body, failed = summary(results.merge('Windows-2022' => { 'status' => 'skipped', 'reason' => 'agent_unavailable' }, 'Ubuntu-24.04' => { 'status' => 'success' }))
      expect(failed).to eq([])
      expect(body).not_to include('stays red')
    end
  end
end
