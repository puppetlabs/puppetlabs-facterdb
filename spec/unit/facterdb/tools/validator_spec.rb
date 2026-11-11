# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::Validator do
  let(:config) { Puppetlabs::FacterDB::Tools::Config.load }
  let(:root) { Dir.mktmpdir }

  after(:each) { FileUtils.remove_entry(root) }

  def scrubber
    Puppetlabs::FacterDB::Tools::Scrubber.new(config.scrub_policy)
  end

  def normaliser
    Puppetlabs::FacterDB::Tools::Normaliser.new(scrubber)
  end

  def validator
    described_class.new(config: config, scrubber: scrubber, normaliser: normaliser)
  end

  def base
    { 'facterversion' => '4.11.0', 'os' => { 'family' => 'Debian' } }
  end

  def put(rel, content)
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def put_rendered(rel, data = base)
    put(rel, normaliser.render(data))
  end

  def messages
    validator.validate(root).map(&:message)
  end

  describe '#validate' do
    it 'accepts a valid normalised file' do
      put_rendered('4.11/debian-12-x86_64.facts')
      expect(validator.validate(root)).to eq([])
    end

    it 'accepts a root with a trailing slash' do
      put_rendered('4.11/debian-12-x86_64.facts')
      expect(validator.validate("#{root}/")).to eq([])
    end

    it 'ignores non-facts files' do
      ['.gitkeep', 'seed-manifest.json'].each { |name| put(name, 'not json') }
      expect(validator.validate(root)).to eq([])
    end

    it 'reports invalid JSON as the only error for the file' do
      put('4.11/debian-12-x86_64.facts', '{nope')
      expect(messages).to match([%r{invalid JSON}])
    end

    it 'does not echo file content in the invalid JSON message' do
      put('4.11/debian-12-x86_64.facts', '{"secret_value": nope')
      expect(messages.join).not_to include('secret_value')
    end

    it 'rejects a non-object top level' do
      put('4.11/debian-12-x86_64.facts', "[1]\n")
      expect(messages).to include(%r{must be a JSON object})
    end

    it 'rejects a facterversion that does not match the directory' do
      put_rendered('4.11/debian-12-x86_64.facts', base.merge('facterversion' => '4.10.0'))
      expect(messages).to include('facterversion 4.10.0 does not match directory 4.11')
    end

    it 'rejects a missing facterversion' do
      put_rendered('4.11/debian-12-x86_64.facts', 'os' => {})
      expect(messages).to include(%r{facterversion})
    end

    it 'rejects a file directly under the root' do
      put_rendered('debian-12-x86_64.facts')
      expect(messages).to include(%r{major\.minor directory})
    end

    it 'rejects a file under a non major.minor directory' do
      put_rendered('latest/debian-12-x86_64.facts')
      expect(messages).to include(%r{major\.minor directory})
    end

    it 'rejects an unsorted file' do
      put('4.11/debian-12-x86_64.facts', "{\"os\": {}, \"facterversion\": \"4.11.0\"}\n")
      expect(messages).to include(%r{not normalised})
    end

    context 'with a real-looking ssh key' do
      let(:key) { 'AAAAB3NzaC1yc2EAAAADAQABAAABAQCrealkeymaterial' }

      before(:each) do
        data = base.merge('ssh' => { 'rsa' => { 'key' => key } })
        put('4.11/debian-12-x86_64.facts', Puppetlabs::FacterDB::Tools::Normaliser.format(data))
      end

      it 'reports the leaked path' do
        expect(messages).to include(%r{scrub leak at ssh\.rsa\.key})
      end

      it 'does not echo the value' do
        expect(messages.join).not_to include(key)
      end
    end

    context 'with cloud metadata' do
      it 'reports a non-empty az_metadata and normalise empties it' do # rubocop:disable RSpec/MultipleExpectations
        data = base.merge('az_metadata' => { 'compute' => { 'name' => 'vm' } })
        put('4.11/debian-12-x86_64.facts', Puppetlabs::FacterDB::Tools::Normaliser.format(data))
        expect(messages).to include(%r{scrub leak at az_metadata})
        expect(normaliser.render(data)).to include('"az_metadata": {}')
      end
    end

    context 'with leak patterns' do
      def put_leaky(extra)
        put('4.11/debian-12-x86_64.facts', Puppetlabs::FacterDB::Tools::Normaliser.format(base.merge(extra)))
      end

      it 'reports the runner home by pattern name and path without the value' do # rubocop:disable RSpec/MultipleExpectations
        put_leaky('path' => '/home/runner/work/bin')
        expect(messages).to include("leak pattern 'github-runner-home' at path")
        expect(messages.join).not_to include('/home/runner')
      end

      it 'reports nested cloud DNS values by dotted path only' do # rubocop:disable RSpec/MultipleExpectations
        put_leaky('networking' => { 'search' => ['vm1.internal.cloudapp.net'] })
        expect(messages).to include("leak pattern 'azure-internal-dns' at networking.search.0")
        expect(messages.join).not_to include('vm1')
      end
    end

    context 'with problems in several files' do
      before(:each) do
        put('4.11/debian-12-x86_64.facts', '{nope')
        put_rendered('4.11/Bad Name.facts')
      end

      it 'reports every file with its relative path' do
        expect(validator.validate(root).map(&:path).uniq).to eq(['4.11/Bad Name.facts', '4.11/debian-12-x86_64.facts'])
      end
    end
  end

  describe '.filename_valid?' do
    [
      'debian-12-x86_64', 'ubuntu-22.04-aarch64', 'popos-21.10-x86_64', 'windows-2016-core-x86_64',
      'windows-2012r2-x86_64', 'solaris-11-sun4v', 'debian-12-i386'
    ].each do |name|
      it "accepts #{name}" do
        expect(described_class.filename_valid?("#{name}.facts", [])).to be(true)
      end
    end

    it 'accepts an allowlisted rolling distro' do
      expect(described_class.filename_valid?('archlinux-x86_64.facts', ['archlinux'])).to be(true)
    end

    ['windows-2012 r2-x86_64.facts', 'Debian-12-x86_64.facts', 'debian-x86_64.facts', 'debian-12.facts'].each do |name|
      it "rejects #{name}" do
        expect(described_class.filename_valid?(name, config.rolling_distros)).to be(false)
      end
    end
  end

  describe 'Config leak_patterns' do
    def build(scrub)
      Puppetlabs::FacterDB::Tools::Config.new('config/scrub.yml', scrub, 'config/facts.yml', 'rolling_distros' => [])
    end

    it 'is empty when leak_patterns is absent' do
      expect(build('scrub' => {}).leak_patterns).to eq([])
    end

    it 'compiles patterns honouring ignore_case' do
      cfg = build('scrub' => {}, 'leak_patterns' => [{ 'name' => 'x', 'regex' => 'abc', 'ignore_case' => true }])
      expect(cfg.leak_patterns).to eq([['x', %r{abc}i]])
    end

    it 'raises ArgumentError naming the file and pattern for an invalid regex' do
      expect { build('scrub' => {}, 'leak_patterns' => [{ 'name' => 'bad', 'regex' => '(' }]) }
        .to raise_error(ArgumentError, %r{config/scrub\.yml.*'bad'})
    end
  end
end
