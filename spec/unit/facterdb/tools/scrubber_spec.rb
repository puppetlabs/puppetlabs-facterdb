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

  describe 'wildcard exclusion' do
    let(:scrubber) { described_class.new('networking.interfaces.*!lo.ip' => '10.0.2.15') }
    let(:data) do
      { 'networking' => { 'interfaces' => { 'lo' => { 'ip' => '127.0.0.1' }, 'eth0' => { 'ip' => '10.1.1.1' },
                                            'ens4' => { 'ip' => '10.2.2.2' }, 'lo0' => { 'ip' => '127.0.0.1' } } } }
    end

    it 'skips the excluded key and matches every other' do
      ips = scrubber.scrub(data)['networking']['interfaces'].transform_values { |iface| iface['ip'] }
      expect(ips).to eq('lo' => '127.0.0.1', 'eth0' => '10.0.2.15', 'ens4' => '10.0.2.15', 'lo0' => '10.0.2.15')
    end

    it 'does not report the excluded key as a leak' do
      expect(scrubber.leaks(data)).to contain_exactly('networking.interfaces.eth0.ip', 'networking.interfaces.ens4.ip',
                                                      'networking.interfaces.lo0.ip')
    end

    it 'excludes several keys when comma separated' do
      both = described_class.new('i.*!lo,lo0.ip' => 'x')
      expect(both.scrub('i' => { 'lo' => { 'ip' => 'a' }, 'lo0' => { 'ip' => 'b' }, 'eth0' => { 'ip' => 'c' } })['i'])
        .to eq('lo' => { 'ip' => 'a' }, 'lo0' => { 'ip' => 'b' }, 'eth0' => { 'ip' => 'x' })
    end
  end

  describe 'pattern rules' do
    profile = 'C:\Users\jdoe\AppData;C:\Users\jdoe;C:\Users\foo\bin'
    let(:policy) do
      {
        'user' => { 'match' => '(?i)\A(?!foo\\\\)[^\\\\]+\\\\.*\z', 'value' => 'FOO\foo' },
        'path' => { 'match' => '(?<=C:\\\\Users\\\\)(?!foo(?:[\\\\;]|\z))[^\\\\;]+', 'value' => 'foo' },
        'tag' => { 'match' => '\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z', 'value' => 'None' },
      }
    end
    let(:scrubber) { described_class.new(policy) }

    it 'replaces the whole value when a match covers it' do
      data = { 'user' => 'LITMUS-1\litmusabc', 'tag' => '1df5c096-6978-ae9a-48af-f17599e1884c' }
      expect(scrubber.scrub(data)).to eq('user' => 'FOO\foo', 'tag' => 'None')
    end

    it 'leaves non-matching values alone' do
      same = { 'user' => 'root', 'tag' => 'None' }
      expect(scrubber.scrub(same)).to eq(same)
    end

    it 'leaves an existing FOO host alone' do
      expect(scrubber.scrub('user' => 'FOO\vagrant')).to eq('user' => 'FOO\vagrant')
    end

    it 'substitutes only the user segment' do
      expect(scrubber.scrub('path' => profile)['path']).to eq('C:\Users\foo\AppData;C:\Users\foo;C:\Users\foo\bin')
    end

    it 'is idempotent' do
      data = { 'user' => 'X\y', 'path' => profile, 'tag' => '1DF5C096-6978-AE9A-48AF-F17599E1884C' }
      once = scrubber.scrub(data)
      expect(scrubber.scrub(once)).to eq(once)
    end

    it 'never converts non-strings or nil' do
      data = { 'user' => nil, 'path' => ['C:\Users\jdoe'], 'tag' => { 'a' => 1 } }
      expect(scrubber.scrub(data)).to eq(data)
    end

    it 'treats missing paths as no-ops' do
      expect(scrubber.scrub({})).to eq({})
    end
  end

  describe 'since rules' do
    let(:scrubber) do
      described_class.new('ip' => { 'since' => '4.12', 'value' => '10.0.2.15' },
                          'user' => { 'since' => '4.12', 'match' => '\Aroot\z', 'value' => 'foo' },
                          'host' => 'always')
    end

    def facts(version)
      { 'facterversion' => version, 'ip' => '10.1.1.1', 'user' => 'root', 'host' => 'x' }.compact
    end

    it 'applies at the since version and later' do
      expect(['4.12.0', '4.12.1', '4.13.0', '5.0.0'].map { |v| scrubber.scrub(facts(v))['ip'] }.uniq).to eq(['10.0.2.15'])
    end

    it 'applies match rules at the since version' do
      expect(scrubber.scrub(facts('4.12.0'))['user']).to eq('foo')
    end

    it 'does not apply to older versions but still applies rules without since' do
      expect(scrubber.scrub(facts('4.11.0'))).to eq('facterversion' => '4.11.0', 'ip' => '10.1.1.1', 'user' => 'root', 'host' => 'always')
    end

    it 'does not apply when facterversion is absent, nil or unparseable' do
      expect([nil, 'not-a-version', 7].map { |v| scrubber.scrub(facts(v))['ip'] }).to eq(['10.1.1.1'] * 3)
    end

    it 'reports since leaks only for files in scope' do
      expect([scrubber.leaks(facts('4.12.0')), scrubber.leaks(facts('4.11.0')), scrubber.leaks(facts('x'))])
        .to eq([['ip', 'user', 'host'], ['host'], ['host']])
    end

    it 'is idempotent' do
      once = scrubber.scrub(facts('4.12.0'))
      expect(scrubber.scrub(once)).to eq(once)
    end
  end

  describe 'shipped policy' do
    let(:facts) do
      { 'facterversion' => '4.12.0', 'identity' => { 'user' => 'LITMUS-1\litmusx' },
        'dmi' => { 'board' => { 'asset_tag' => '1DF5C096-6978-AE9A-48AF-F17599E1884C' } },
        'networking' => { 'mac' => '42:01:0a:d9:00:02', 'interfaces' => { 'lo' => { 'ip' => '127.0.0.1' }, 'ens4' => { 'ip' => '172.17.0.2' } } } }
    end

    it 'scrubs 4.12 network, user and asset tag but leaves lo' do
      scrubbed = scrubber.scrub(facts)
      expect([scrubbed['identity'], scrubbed['dmi'], scrubbed['networking']]).to eq(
        [{ 'user' => 'FOO\foo' }, { 'board' => { 'asset_tag' => 'None' } },
         { 'mac' => '08:00:27:8d:c0:4d', 'interfaces' => { 'lo' => { 'ip' => '127.0.0.1' }, 'ens4' => { 'ip' => '10.0.2.15' } } }],
      )
    end

    it 'leaves 4.11 facts alone' do
      old = facts.merge('facterversion' => '4.11.0')
      expect(scrubber.scrub(old)).to eq(old)
    end

    context 'with dhcp, network6 and bindings6 network values' do
      def net_facts(version)
        iface = { 'dhcp' => '10.32.22.10', 'network6' => '2aa1:1470:5ab6::', 'bindings6' => [{ 'network' => '2aa1:1470:5ab6::' }] }
        lo = { 'dhcp' => nil, 'network6' => '::1', 'bindings6' => [{ 'network' => '::1' }] }
        { 'facterversion' => version,
          'networking' => iface.merge('interfaces' => { 'eth0' => iface, 'lo' => lo, 'eth1' => { 'mtu' => 1500 } }) }
      end

      it 'replaces the top level values on 4.12' do
        expect(scrubber.scrub(net_facts('4.12.0'))['networking'].slice('dhcp', 'network6')).to eq('dhcp' => '10.0.2.2', 'network6' => 'fe80::')
      end

      it 'replaces interface values on 4.12 but leaves lo and absent keys alone' do
        expect(scrubber.scrub(net_facts('4.12.0'))['networking']['interfaces']).to eq(
          'eth0' => { 'dhcp' => '10.0.2.2', 'network6' => 'fe80::', 'bindings6' => [{ 'network' => 'fe80::' }] },
          'lo' => { 'dhcp' => nil, 'network6' => '::1', 'bindings6' => [{ 'network' => '::1' }] },
          'eth1' => { 'mtu' => 1500 },
        )
      end

      it 'is idempotent' do
        once = scrubber.scrub(net_facts('4.12.0'))
        expect(scrubber.scrub(once)).to eq(once)
      end

      it 'leaves 4.11 facts unchanged' do
        expect(scrubber.scrub(net_facts('4.11.0'))).to eq(net_facts('4.11.0'))
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
