# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::Seeder do
  let(:tools) { Puppetlabs::FacterDB::Tools }
  let(:config) { tools::Config.load }
  let(:source) { Dir.mktmpdir }
  let(:dest) { Dir.mktmpdir }

  after(:each) do
    FileUtils.remove_entry(source)
    FileUtils.remove_entry(dest)
  end

  def today
    Date.new(2026, 1, 2)
  end

  def normaliser
    tools::Normaliser.new(tools::Scrubber.new(config.scrub_policy))
  end

  def git(*args)
    out, status = Open3.capture2e('git', '-C', source, '-c', 'user.name=spec', '-c', 'user.email=spec@example.com', '-c', 'commit.gpgsign=false', *args)
    raise out unless status.success?

    out
  end

  def put(rel, content, root: source)
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def put_fact(rel, version, extra = {})
    put(rel, JSON.generate({ 'facterversion' => version, 'os' => { 'family' => 'Debian' } }.merge(extra)))
  end

  def init_repo(remote: nil)
    git('init', '-q')
    git('remote', 'add', 'origin', remote) if remote
    git('add', '.')
    git('commit', '-q', '-m', 'seed')
  end

  def seeder(**opts)
    described_class.new(source: source, dest: dest, config: config, normaliser: normaliser, today: today, **opts)
  end

  def run_seed(**opts)
    init_repo(**opts) unless File.directory?(File.join(source, '.git'))
    seeder.run
  end

  def dest_snapshot
    Dir.glob('**/*', base: dest).select { |f| File.file?(File.join(dest, f)) }.to_h do |f|
      stat = File.stat(File.join(dest, f))
      [f, [stat.mtime, File.binread(File.join(dest, f))]]
    end
  end

  def skip_reasons(report)
    report.skipped.to_h { |e| [e['source_path'], e['reason']] }
  end

  context 'with a plain source file' do
    before(:each) { put_fact('facts/4.10/debian-12-x86_64.facts', '4.10.0', 'zeta' => 1, 'alpha' => 2) }

    it 'writes the normalised, sorted rendering' do
      run_seed
      data = JSON.parse(File.read(File.join(source, 'facts/4.10/debian-12-x86_64.facts')))
      expect(File.read(File.join(dest, '4.10/debian-12-x86_64.facts'))).to eq(normaliser.render(data))
    end

    it 'ignores non-fact files and windows_packer' do
      put('facts/README.md', 'x')
      put('facts/Vagrantfile', 'x')
      put_fact('facts/windows_packer/10/win-1-x86_64.facts', '4.10.0')
      report = run_seed
      expect(report.seeded.size).to eq(1)
    end

    it 'records a manifest with relative paths only', :aggregate_failures do
      report = run_seed
      manifest = JSON.parse(File.read(File.join(dest, 'seed-manifest.json')))
      expect(manifest.keys).to include('source_repo', 'source_commit', 'source_dirty', 'seeded_on', 'facter_range', 'counts', 'files', 'renamed', 'skipped', 'superseded', 'kept')
      expect(report.changed).to be(true)
    end

    it 'records no absolute or temp paths' do
      run_seed
      text = File.read(File.join(dest, 'seed-manifest.json')) + File.read(File.join(dest, 'PROVENANCE.md'))
      expect(text).not_to include(source, dest)
    end

    it 'records facter range, date and counts', :aggregate_failures do
      run_seed
      manifest = JSON.parse(File.read(File.join(dest, 'seed-manifest.json')))
      expect(manifest).to include('facter_range' => '4.0-4.11', 'seeded_on' => '2026-01-02')
      expect(manifest['counts']['seeded']).to eq(1)
    end

    it 'renders PROVENANCE.md with sha and attribution' do
      run_seed
      sha = git('rev-parse', 'HEAD').strip
      md = File.read(File.join(dest, 'PROVENANCE.md'))
      expect(md).to include(sha, '../NOTICE', 'voxpupuli/facterdb', 'Apache-2.0')
    end

    it 'does not write anything on a second run', :aggregate_failures do
      run_seed
      before = dest_snapshot
      sleep 0.01
      expect(seeder.run.changed).to be(false)
      expect(dest_snapshot).to eq(before)
    end

    it 'flags a dirty source checkout' do
      init_repo
      put('untracked.txt', 'x')
      seeder.run
      expect(JSON.parse(File.read(File.join(dest, 'seed-manifest.json')))['source_dirty']).to be(true)
    end
  end

  context 'with a remote url containing credentials' do
    it 'strips userinfo' do
      put_fact('facts/4.10/debian-12-x86_64.facts', '4.10.0')
      init_repo(remote: 'https://user:secret@github.com/x/y.git')
      seeder.run
      repo = JSON.parse(File.read(File.join(dest, 'seed-manifest.json')))['source_repo']
      expect(repo).to eq('https://github.com/x/y.git')
    end
  end

  context 'when keyed by inner facterversion' do
    it 'writes under the inner major.minor directory' do
      put_fact('facts/4.10/debian-12-x86_64.facts', '4.11.0')
      run_seed
      expect(File).to exist(File.join(dest, '4.11/debian-12-x86_64.facts'))
    end
  end

  context 'with out-of-range or broken files' do
    before(:each) do
      put_fact('facts/5.0/a-1-x86_64.facts', '5.0.1')
      put_fact('facts/3.14/b-1-x86_64.facts', '3.14.0')
      put_fact('facts/4.12/c-1-x86_64.facts', '4.12.0')
      put('facts/4.5/d-1-x86_64.facts', JSON.generate('os' => {}))
      put('facts/4.5/e-1-x86_64.facts', JSON.generate('facterversion' => 'garbled'))
      put('facts/4.5/f-1-x86_64.facts', '{not json')
      put_fact('facts/4.5/Bad Name.facts', '4.5.0')
    end

    let(:reasons) { skip_reasons(run_seed) }

    it 'skips OpenFact, pre-4.x and out-of-range versions', :aggregate_failures do
      expect(reasons['facts/5.0/a-1-x86_64.facts']).to include('OpenFact')
      expect(reasons['facts/3.14/b-1-x86_64.facts']).to include('pre-4.x')
      expect(reasons['facts/4.12/c-1-x86_64.facts']).to include('outside seed range 4.0-4.11')
    end

    it 'skips unparseable and badly named files', :aggregate_failures do
      expect(reasons['facts/4.5/d-1-x86_64.facts']).to include('facterversion')
      expect(reasons['facts/4.5/e-1-x86_64.facts']).to include('facterversion')
      expect(reasons['facts/4.5/f-1-x86_64.facts']).to include('invalid JSON')
      expect(reasons['facts/4.5/Bad Name.facts']).to include('filename')
    end

    it 'writes nothing' do
      run_seed
      expect(Dir.glob('**/*.facts', base: dest)).to be_empty
    end
  end

  context 'with a filename needing a rename' do
    it 'writes the renamed target and records it', :aggregate_failures do
      put_fact('facts/4.2/windows-2012 r2-x86_64.facts', '4.2.0')
      report = run_seed
      expect(File).to exist(File.join(dest, '4.2/windows-2012r2-x86_64.facts'))
      expect(report.renamed).to eq([{ 'source_path' => 'facts/4.2/windows-2012 r2-x86_64.facts', 'target' => 'windows-2012r2-x86_64.facts' }])
      expect(File.read(File.join(dest, 'seed-manifest.json'))).to include('windows-2012r2-x86_64.facts')
    end
  end

  context 'with colliding targets' do
    before(:each) do
      put_fact('facts/4.2/debian-12-x86_64.facts', '4.2.2')
      put_fact('facts/4.3/debian-12-x86_64.facts', '4.2.14')
    end

    it 'keeps the highest patch by Gem::Version', :aggregate_failures do
      report = run_seed
      expect(JSON.parse(File.read(File.join(dest, '4.2/debian-12-x86_64.facts')))['facterversion']).to eq('4.2.14')
      expect(report.superseded.map { |e| e['version'] }).to eq(['4.2.2'])
    end
  end

  context 'with an existing destination file' do
    before(:each) { put_fact('facts/4.2/debian-12-x86_64.facts', '4.2.10') }

    it 'keeps a higher-patch existing file', :aggregate_failures do
      put(File.join('4.2', 'debian-12-x86_64.facts'), normaliser.render('facterversion' => '4.2.14'), root: dest)
      report = run_seed
      expect(JSON.parse(File.read(File.join(dest, '4.2/debian-12-x86_64.facts')))['facterversion']).to eq('4.2.14')
      expect(report.kept.size).to eq(1)
    end

    it 'overwrites a lower-patch existing file' do
      put(File.join('4.2', 'debian-12-x86_64.facts'), normaliser.render('facterversion' => '4.2.2'), root: dest)
      run_seed
      expect(JSON.parse(File.read(File.join(dest, '4.2/debian-12-x86_64.facts')))['facterversion']).to eq('4.2.10')
    end
  end

  context 'when the source is not a git checkout' do
    it 'raises an error mentioning git' do
      expect { seeder.run }.to raise_error(ArgumentError, %r{git})
    end
  end

  describe 'Report#to_s' do
    it 'lists sections and the change summary' do
      put_fact('facts/5.0/a-1-x86_64.facts', '5.0.1')
      put_fact('facts/4.2/debian-12-x86_64.facts', '4.2.2')
      text = run_seed.to_s
      expect(text).to include('Seeded: 1', 'Skipped:', 'Wrote changes')
    end
  end
end
