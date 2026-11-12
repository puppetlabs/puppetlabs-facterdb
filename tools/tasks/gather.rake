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
end
