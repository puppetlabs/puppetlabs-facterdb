# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'GitHub workflows' do # rubocop:disable RSpec/DescribeClass
  workflows_dir = File.expand_path('../../.github/workflows', __dir__)
  workflows = Dir.glob(File.join(workflows_dir, '*.yml')).to_h { |path| [File.basename(path), YAML.safe_load_file(path)] }

  def triggers(workflow)
    workflow['on'] || workflow[true]
  end

  def steps_of(job)
    job.fetch('steps', [])
  end

  let(:gather) { workflows.fetch('gather-facts.yml') }
  let(:ci) { workflows.fetch('ci.yml') }
  let(:collect_steps) { steps_of(gather['jobs']['collect']) }

  workflows.each do |name, workflow|
    it "pins every action in #{name} to a full commit SHA" do
      uses = workflow['jobs'].values.flat_map { |job| job.fetch('steps', []) }.filter_map { |step| step['uses'] }
      expect(uses).not_to be_empty
      expect(uses).to all(match(%r{\A[\w.-]+/[\w./-]+@[0-9a-f]{40}\z}))
    end

    it "never uses set -x in #{name}" do
      runs = workflow['jobs'].values.flat_map { |job| job.fetch('steps', []) }.filter_map { |step| step['run'] }
      runs.each { |run| expect(run).not_to include('set -x') }
    end
  end

  it 'triggers gather-facts only on dispatch and schedule' do
    expect(triggers(gather).keys).to contain_exactly('workflow_dispatch', 'schedule')
  end

  it 'requires the facter_version input' do
    expect(triggers(gather)['workflow_dispatch']['inputs']['facter_version']['required']).to be(true)
  end

  it 'keeps top-level permissions read-only' do
    expect(gather['permissions']).to eq('contents' => 'read')
  end

  it 'gives collect only contents and pull-requests write' do
    expect(gather['jobs']['collect']['permissions']).to eq('contents' => 'write', 'pull-requests' => 'write')
  end

  it 'runs plan and gather in the puppetcore environment' do
    expect(gather['jobs']['plan']['environment']).to eq('puppetcore')
    expect(gather['jobs']['gather']['environment']).to eq('puppetcore')
  end

  it 'gives collect no environment and no Core secret' do
    expect(gather['jobs']['collect']).not_to have_key('environment')
    expect(gather['jobs']['collect'].to_s).not_to include('PUPPET_FORGE_TOKEN')
  end

  it 'never interpolates expressions into run blocks' do
    runs = gather['jobs'].values.flat_map { |job| job['steps'] }.filter_map { |step| step['run'] }
    expect(runs).not_to be_empty
    runs.each { |run| expect(run).not_to include('${{') }
  end

  it 'caps and times out the gather matrix without fail-fast' do
    job = gather['jobs']['gather']
    expect(job['strategy']['fail-fast']).to be(false)
    expect(job['strategy']['max-parallel']).to be_an(Integer)
    expect(job['timeout-minutes']).to be_an(Integer)
  end

  it 'fails the run after the create-pull-request step' do
    uses = collect_steps.map { |step| step['uses'].to_s }
    pr_index = uses.index { |value| value.start_with?('peter-evans/create-pull-request@') }
    fail_index = collect_steps.index { |step| step['if'] == "steps.collect.outputs.failed == 'true'" }
    expect(pr_index).not_to be_nil
    expect(fail_index).to be > pr_index
  end

  it 'keeps ci.yml free of secrets' do
    expect(ci.to_s).not_to include('secrets.')
    expect(File.read(File.join(workflows_dir, 'ci.yml'))).not_to include('secrets.')
  end
end
# rubocop:enable RSpec/MultipleExpectations
