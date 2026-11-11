# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'puppetlabs/facterdb/tools'

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
RSpec.describe Puppetlabs::FacterDB::Tools::Store do
  let(:root) { Dir.mktmpdir }
  let(:facts_dir) { File.join(root, 'facts') }
  let(:artifacts) { File.join(root, 'artifacts') }
  let(:id) { 'ubuntu-24.04-x86_64' }
  let(:version) { '4.23.0' }
  let(:target) { File.join(facts_dir, '4.23', "#{id}.facts") }
  let(:platforms) do
    entry = {
      'id' => id, 'os' => 'ubuntu', 'release' => '24.04', 'arch' => 'x86_64', 'family' => 'linux',
      'backend' => 'container', 'runner' => 'ubuntu-24.04', 'image' => 'litmusimage/ubuntu:24.04', 'repo_id' => 'noble'
    }
    old = entry.merge('id' => 'debian-9-x86_64', 'os' => 'debian', 'release' => '9', 'skip' => 'EOL')
    core = [{ 'os' => 'ubuntu', 'release' => '24.04', 'arch' => 'x86_64' }]
    Puppetlabs::FacterDB::Tools::Platforms.new('p.yml', { 'platforms' => [entry, old] }, 'c.yml', { 'core_supported' => core })
  end
  let(:store) { described_class.new(platforms: platforms, facts_dir: facts_dir, version: version) }

  after(:each) { FileUtils.remove_entry(root) }

  def facts(overrides = {})
    {
      'facterversion' => version,
      'os' => { 'name' => 'Ubuntu', 'release' => { 'major' => '24.04' }, 'hardware' => 'x86_64' },
    }.merge(overrides)
  end

  def leg(leg_id, outcome, data: nil, reason: '', raw: nil)
    dir = File.join(artifacts, "gather-#{leg_id}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'result.json'), JSON.generate('id' => leg_id, 'outcome' => outcome, 'reason' => reason))
    File.write(File.join(dir, 'facts.json'), raw || JSON.generate(data)) if raw || data
  end

  def file_count
    Dir.glob('**/*', base: facts_dir).count { |f| File.file?(File.join(facts_dir, f)) }
  end

  def place(ids = [id], **opts)
    store.place(artifacts, ids, **opts)
  end

  it 'adds a new file under the major.minor directory' do
    leg(id, 'gathered', data: facts)
    outcome = place.first
    expect([outcome.outcome, outcome.action, outcome.path]).to eq(['gathered', 'added', target])
    expect(JSON.parse(File.read(target))['facterversion']).to eq(version)
    expect(outcome.method).to eq('container (litmusimage/ubuntu:24.04)')
  end

  it 'reports changed when overwriting a same-version file' do
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, JSON.generate('facterversion' => version, 'old' => true))
    leg(id, 'gathered', data: facts)
    expect(place.first.action).to eq('changed')
    expect(JSON.parse(File.read(target))).not_to have_key('old')
  end

  it 'keeps a newer stored patch (kept_newer)' do
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, JSON.generate('facterversion' => '4.23.1'))
    leg(id, 'gathered', data: facts)
    outcome = place.first
    expect([outcome.outcome, outcome.action]).to eq(['gathered', 'kept_newer'])
    expect(JSON.parse(File.read(target))['facterversion']).to eq('4.23.1')
  end

  it 'fails on facterversion mismatch without writing' do
    leg(id, 'gathered', data: facts('facterversion' => '4.22.0'))
    outcome = place.first
    expect([outcome.outcome, outcome.reason]).to eq(['failed', 'facterversion mismatch'])
    expect(File.exist?(target)).to be(false)
  end

  it 'fails on identity mismatch naming the computed id only' do
    data = facts
    data['os']['hardware'] = 'aarch64'
    data['secret'] = 'do-not-echo'
    leg(id, 'gathered', data: data)
    outcome = place.first
    expect(outcome.outcome).to eq('failed')
    expect(outcome.reason).to include('identity mismatch', 'ubuntu-24.04-aarch64')
    expect(outcome.reason).not_to include('do-not-echo')
    expect(File.exist?(target)).to be(false)
  end

  it 'passes through skipped and failed results with their reason' do
    leg(id, 'skipped', reason: 'no Core package')
    expect(place.first.to_h.values_at(:outcome, :reason)).to eq(['skipped', 'no Core package'])
    leg(id, 'failed', reason: 'install error')
    expect(place.first.to_h.values_at(:outcome, :reason)).to eq(['failed', 'install error'])
    expect(file_count).to eq(0)
  end

  it 'fails a selected id with no artifact' do
    outcome = place.first
    expect([outcome.outcome, outcome.reason]).to eq(['failed', 'no result artifact'])
  end

  it 'ignores artifacts that are not selected or have an invalid id' do
    leg(id, 'gathered', data: facts)
    leg('../evil', 'gathered', data: facts)
    expect(place(['../evil']).size).to eq(0)
    expect(place(['debian-11-x86_64']).map(&:id)).to eq(['debian-11-x86_64'])
    expect(file_count).to eq(0)
  end

  it 'fails when facts.json is not a JSON object' do
    leg(id, 'gathered', raw: '["secret"]')
    outcome = place.first
    expect([outcome.outcome, outcome.reason]).to eq(['failed', 'invalid facts JSON'])
  end

  it 'strips control characters and truncates reasons' do
    leg(id, 'failed', reason: "bad\n| #{'x' * 300}")
    reason = place.first.reason
    expect(reason).not_to match(%r{[[:cntrl:]]})
    expect(reason.length).to be <= 200
  end

  it 'lists config skips only when unfiltered' do
    leg(id, 'gathered', data: facts)
    expect(place.map(&:id)).to eq([id])
    outcomes = place(unfiltered: true)
    expect(outcomes.map(&:id)).to eq([id, 'debian-9-x86_64'])
    expect(outcomes.last.to_h.values_at(:outcome, :reason)).to eq(['skipped', 'EOL'])
  end

  it 'reports failed? only for failed outcomes' do
    leg(id, 'gathered', data: facts)
    expect(store.failed?(place(unfiltered: true))).to be(false)
    expect(store.failed?(place([id, 'debian-11-x86_64']))).to be(true)
  end

  it 'never decreases the file count across scenarios' do
    leg(id, 'gathered', data: facts)
    place
    before = file_count
    leg(id, 'failed', reason: 'boom')
    place
    leg(id, 'gathered', data: facts('facterversion' => '4.1.0'))
    place
    expect(file_count).to be >= before
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
