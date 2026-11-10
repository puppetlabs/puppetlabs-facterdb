# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::Scrubber do
  let(:config) { Puppetlabs::FacterDB::Tools::Config.load }
  let(:scrubber) { described_class.new(config.scrub_policy) }
  let(:real_key) { 'AAAAB3NzaC1yc2EAAAADAQABAAABAQC7realkey' }
  let(:data) do
    {
      'system_uptime' => { 'seconds' => 1234, 'hours' => 0, 'days' => 0, 'uptime' => '0:20 hours' },
      'ssh' => { 'rsa' => { 'key' => real_key, 'type' => 'ssh-rsa',
                            'fingerprints' => { 'sha1' => 'SSHFP 1 1 abc', 'sha256' => 'SSHFP 1 2 def' } } },
      'disks' => { 'sda' => { 'serial' => 'VB123', 'size' => '1 GiB' }, 'sdb' => { 'size' => '2 GiB' } },
      'partitions' => { '/dev/sda1' => { 'uuid' => 'abc' }, '/dev/sda2' => {} },
      'mountpoints' => { '/vagrant' => { 'device' => '10.0.0.1:/System/Volumes/Data/Users/someone/git/facterdb/facts' } },
      'networking' => { 'ip' => '10.138.1.5', 'mac' => '08:00:27:aa:bb:cc',
                        'interfaces' => { 'eth0' => { 'mac' => '08:00:27:aa:bb:cc' } } },
    }
  end

  describe '#scrub' do
    subject(:scrubbed) { scrubber.scrub(data) }

    it 'zeroes system_uptime' do
      expect(scrubbed['system_uptime']).to eq('seconds' => 0, 'hours' => 0, 'days' => 0, 'uptime' => '0:00 hours')
    end

    it 'replaces ssh values and leaves the type alone' do
      expect(scrubbed['ssh']['rsa']).to include(
        'key' => 'AAAAscrubbed',
        'type' => 'ssh-rsa',
        'fingerprints' => { 'sha1' => "SSHFP 1 1 #{'0' * 40}", 'sha256' => "SSHFP 1 2 #{'0' * 64}" },
      )
    end

    it 'applies wildcard paths to every child that has the leaf' do
      expect(scrubbed['disks']['sda']['serial']).to eq('0')
    end

    it 'skips wildcard children without the leaf' do
      expect(scrubbed['disks']['sdb']).to eq('size' => '2 GiB')
    end

    it 'does not add keys for missing paths' do
      expect(scrubbed['ssh']).not_to have_key('dsa')
    end

    it 'is idempotent' do
      expect(scrubber.scrub(scrubbed)).to eq(scrubbed)
    end

    it 'does not mutate its input' do
      expect { scrubber.scrub(data) }.not_to(change { Marshal.dump(data) })
    end

    it 'rewrites the NFS device that leaks a username' do
      expect(scrubbed['mountpoints']['/vagrant']['device']).to eq('10.0.0.1:/vagrant')
    end

    it 'leaves networking ip and mac alone' do
      expect(scrubbed['networking']).to eq(data['networking'])
    end

    context 'with a changed placeholder in a config file' do
      let(:custom_root) do
        dir = Dir.mktmpdir
        FileUtils.mkdir_p(File.join(dir, 'config'))
        FileUtils.cp(File.join(Puppetlabs::FacterDB::Tools::REPO_ROOT, 'config', 'facts.yml'), File.join(dir, 'config'))
        File.write(File.join(dir, 'config', 'scrub.yml'), { 'scrub' => { 'system_uptime.seconds' => 99 } }.to_yaml)
        dir
      end

      after(:each) { FileUtils.remove_entry(custom_root) }

      it 'changes the output with no code change' do
        custom = described_class.new(Puppetlabs::FacterDB::Tools::Config.load(custom_root).scrub_policy)
        expect(custom.scrub(data)['system_uptime']['seconds']).to eq(99)
      end
    end
  end

  describe '#leaks' do
    it 'names the path of a real key' do
      expect(scrubber.leaks(data)).to include('ssh.rsa.key')
    end

    it 'does not expose leaked values' do
      expect(scrubber.leaks(data).join).not_to include(real_key)
    end

    it 'returns concrete paths for wildcard leaks' do
      expect(scrubber.leaks(data)).to include('disks.sda.serial', 'partitions./dev/sda1.uuid')
    end

    it 'returns nothing for scrubbed data' do
      expect(scrubber.leaks(scrubber.scrub(data))).to eq([])
    end
  end
end
