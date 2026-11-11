# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'tools/gather scripts' do # rubocop:disable RSpec/DescribeClass
  gather_dir = File.expand_path('../../../tools/gather', __dir__)
  shell_scripts = ['linux.sh', 'macos.sh'].to_h { |name| [name, File.join(gather_dir, name)] }
  all_scripts = shell_scripts.merge('windows.ps1' => File.join(gather_dir, 'windows.ps1'))

  all_scripts.each do |name, path|
    describe name do
      let(:source) { File.read(path) }

      it 'never enables tracing or passes credentials to curl -u' do
        expect(source).not_to match(%r{set -x|set -o xtrace|xtrace|Set-PSDebug|curl[^\n]*\s-u\s})
      end

      it 'writes result.json with gathered and skipped outcomes' do
        expect(source).to include('result.json').and include('gathered').and include('skipped')
      end

      it 'validates FACTER_VERSION with an anchored X.Y.Z pattern' do
        expect(source).to match(%r{FACTER_VERSION\}?"? =~ \^\[0-9\]\+\\\.\[0-9\]\+\\\.\[0-9\]\+\$|FACTER_VERSION -notmatch '\^\\d\+\\\.\\d\+\\\.\\d\+\$'})
      end

      it 'compares the installed facter --version with FACTER_VERSION' do
        expect(source).to match(%r{--version}).and match(%r{!= \$\{?(env:)?FACTER_VERSION})
      end

      it 'writes only facts.json and result.json into OUT_DIR' do
        written = source.scan(%r{OUT_DIR\}?["']?[/\\ ]?["']?([\w.-]+\.\w+)}).flatten.uniq
        expect(written - ['facts.json', 'result.json']).to eq([])
      end
    end
  end

  shell_scripts.each do |name, path|
    describe name do
      let(:source) { File.read(path) }

      it 'passes bash -n' do
        skip 'bash not available' unless system('command -v bash > /dev/null 2>&1')
        _out, err, status = Open3.capture3('bash', '-n', path)
        expect([status.success?, err]).to eq([true, ''])
      end

      it 'uses an env bash shebang and strict mode' do
        expect(source).to start_with("#!/usr/bin/env bash\n").and include('set -euo pipefail')
      end
    end
  end

  describe 'linux.sh credential and input handling' do
    let(:path) { shell_scripts.fetch('linux.sh') }
    let(:source) { File.read(path) }
    let(:out_dir) { File.join(Dir.mktmpdir, 'out') }
    let(:env) do
      {
        'PUPPET_FORGE_TOKEN' => 'dummy',
        'FACTER_VERSION' => '4.23.0;id',
        'AGENT_VERSION' => '8.22.2',
        'AGENT_MAJOR' => '8',
        'PLATFORM_ID' => 'ubuntu-24.04-x86_64',
        'OUT_DIR' => out_dir,
        'REPO_ID' => 'noble',
      }
    end

    after(:each) { FileUtils.rm_rf(File.dirname(out_dir)) }

    it 'reads the token through awk ENVIRON' do
      expect(source).to include('ENVIRON["PUPPET_FORGE_TOKEN"]')
    end

    it 'never expands the token variable' do
      code = source.gsub('ENVIRON["PUPPET_FORGE_TOKEN"]', '').gsub(%r{^\s*#.*$}, '')
      expect(code.scan(%r{\$\{?PUPPET_FORGE_TOKEN\b})).to eq([])
    end

    it 'rejects an injected FACTER_VERSION with exit 2' do
      skip 'bash not available' unless system('command -v bash > /dev/null 2>&1')
      _out, _err, status = Open3.capture3(env, 'bash', path)
      expect(status.exitstatus).to eq(2)
    end

    it 'creates no output files when input is rejected' do
      skip 'bash not available' unless system('command -v bash > /dev/null 2>&1')
      Open3.capture3(env, 'bash', path)
      expect(File.exist?(out_dir)).to be(false)
    end
  end
end
