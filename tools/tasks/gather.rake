# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'puppetlabs/facterdb/tools'

begin
  require 'puppet_litmus/rake_tasks'
rescue LoadError
  # gather group not installed
end

module GatherTasks
  Tools = Puppetlabs::FacterDB::Tools
  MODULES_FILE = File.join(Tools::REPO_ROOT, 'config', 'litmus_modules.yml')
  FIXTURES = File.join(Tools::REPO_ROOT, 'spec', 'fixtures', 'modules')

  module_function

  def facts_dir
    ENV.fetch('FACTS_DIR', 'facts')
  end

  def write_outputs(outputs)
    lines = outputs.map { |key, value| "#{key}=#{value}\n" }.join
    if ENV['GITHUB_OUTPUT'].to_s.empty?
      print lines
    else
      File.open(ENV.fetch('GITHUB_OUTPUT'), 'a') { |f| f.write(lines) }
    end
  end

  def litmus_modules
    modules = YAML.safe_load_file(MODULES_FILE).fetch('modules')
    modules.each do |name, entry|
      repo = entry.is_a?(Hash) ? entry['repo'].to_s : ''
      ref = entry.is_a?(Hash) ? entry['ref'].to_s : ''
      raise ArgumentError, "#{MODULES_FILE}: #{name} needs an https://github.com/ repo and a ref" unless repo.start_with?('https://github.com/') && !ref.empty?
    end
    modules
  end

  def clone_modules
    litmus_modules.each do |name, entry|
      dest = File.join(FIXTURES, name)
      next if File.exist?(dest)

      system('git', 'clone', '--quiet', '--depth', '1', '--branch', entry['ref'], entry['repo'], dest, exception: true)
    end
  end

  def next_version
    map = Tools::FacterVersions.load
    selected = map.resolve(ENV.fetch('INPUT_VERSION', ''), facts_dir)
    if selected.nil?
      write_outputs('version' => '')
      puts 'nothing to gather'
      return
    end

    agent = map.agent_for(selected)
    write_outputs(
      'version' => selected,
      'agent' => agent,
      'agent_major' => agent.split('.').first,
      'collection' => Tools::FacterVersions.collection_for(agent),
      'major_minor' => selected.split('.').first(2).join('.'),
    )
  rescue ArgumentError => e
    abort e.message
  end

  def fetch!(name)
    value = ENV.fetch(name, '')
    abort "#{name} is not set" if value.empty?
    value
  end

  def facter_command(label)
    label.start_with?('Windows') ? "& 'C:\\Program Files\\Puppet Labs\\Puppet\\bin\\facter.bat'" : '/opt/puppetlabs/bin/facter'
  end

  def litmus_runner
    require 'puppet_litmus'
    runner = Object.new
    runner.extend(PuppetLitmus::InventoryManipulation)
    runner.extend(PuppetLitmus)
    runner
  end

  def select_target(runner)
    targets = runner.find_targets(runner.inventory_hash_from_inventory_file, nil)
    abort "expected exactly one litmus target, found #{targets.size}" unless targets.size == 1
    ENV['TARGET_HOST'] = targets.first
  end

  def check_leg_inputs(facter_version, agent, collection)
    abort 'puppet_litmus is not installed (bundle with the gather group)' unless Rake::Task.task_defined?('litmus:provision')
    abort 'invalid FACTER_VERSION (expected X.Y.Z)' unless facter_version.match?(Tools::FacterVersions::VERSION)
    abort 'invalid AGENT_VERSION (expected X.Y.Z)' unless agent.match?(Tools::FacterVersions::VERSION)

    expected = Tools::FacterVersions.collection_for(agent)
    abort "COLLECTION #{collection} does not match the agent's Puppet Core collection #{expected}" unless collection == expected
  end

  def assert_facter_version(runner, facter, expected)
    actual = runner.run_shell("#{facter} --version").stdout.to_s.strip
    return if actual == expected

    detail = actual.match?(Tools::FacterVersions::VERSION) ? "got #{actual}" : 'unexpected output'
    abort "facter --version mismatch: expected #{expected}, #{detail}"
  end

  def gather_facts(runner, facter)
    JSON.parse(runner.run_shell("#{facter} -j").stdout.to_s)
  rescue JSON::ParserError
    abort 'facter -j returned invalid JSON (details withheld)'
  end

  def leg
    facter_version = fetch!('FACTER_VERSION')
    agent = fetch!('AGENT_VERSION')
    collection = fetch!('COLLECTION')
    label = fetch!('LABEL')
    provider = fetch!('PROVIDER')
    image = fetch!('IMAGE')
    output_dir = fetch!('OUTPUT_DIR')
    fetch!('PUPPET_FORGE_TOKEN')
    check_leg_inputs(facter_version, agent, collection)

    Rake::Task['litmus:provision'].invoke(provider, image)
    ENV['PUPPET_VERSION'] = agent
    Rake::Task['litmus:install_agent'].invoke(collection)

    runner = litmus_runner
    select_target(runner)
    facter = facter_command(label)
    assert_facter_version(runner, facter, facter_version)

    facts = gather_facts(runner, facter)
    path = Tools::Gather.relative_path_for(facts)
    FileUtils.mkdir_p(File.dirname(File.join(output_dir, path)))
    File.write(File.join(output_dir, path), Tools::Gather.render_scrubbed(facts))
    puts path
  rescue ArgumentError => e
    abort e.message
  end

  def collect
    version = fetch!('FACTER_VERSION')
    agent = fetch!('AGENT_VERSION')
    body_path = fetch!('BODY_PATH')
    gathered = fetch!('GATHERED_DIR')
    labels = JSON.parse(fetch!('MATRIX')).fetch('platforms').map { |platform| platform.fetch('label') }
    succeeded = Dir.glob('facts-*', base: gathered).map { |dir| dir.delete_prefix('facts-') }

    result = Tools::Gather.place(gathered, facts_dir, version)
    abort "invalid gathered files: #{result.invalid.join(', ')}" unless result.invalid.empty?

    body, failed = Tools::Gather.summary(labels: labels, succeeded: succeeded, version: version, agent: agent, placed: result.placed, skipped: result.skipped)
    File.write(body_path, body)
    write_outputs('placed' => result.placed.size, 'failed' => !failed.empty?)
  rescue JSON::ParserError, KeyError
    abort 'MATRIX is not valid setup output JSON'
  end
end

unless Rake::Task.task_defined?(:spec_prep)
  desc 'Clone the bolt modules litmus needs into spec/fixtures/modules'
  task :spec_prep do
    GatherTasks.clone_modules
  end
end

unless Rake::Task.task_defined?(:spec_clean)
  desc 'No-op (fixtures are left in place)'
  task :spec_clean
end

namespace :gather do
  desc 'Pick the Facter version to gather and write it to GITHUB_OUTPUT'
  task :next_version do
    GatherTasks.next_version
  end

  desc 'Provision one platform with litmus, install the agent, assert facter --version and save facter -j'
  task :leg do
    GatherTasks.leg
  end

  desc 'Place gathered facts into facts/ and write the PR body'
  task :collect do
    GatherTasks.collect
  end
end
