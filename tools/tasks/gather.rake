# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'puppetlabs/facterdb/tools'

module GatherTasks
  Tools = Puppetlabs::FacterDB::Tools

  module_function

  def platforms
    @platforms ||= Tools::Platforms.load
  end

  def plan_from_env
    Tools::GatherPlan.new(
      event: ENV.fetch('GITHUB_EVENT_NAME', nil),
      facter_version: ENV.fetch('INPUT_FACTER_VERSION', nil),
      platforms_input: ENV.fetch('INPUT_PLATFORMS', nil),
      platforms: platforms,
      version_map: Tools::VersionMap.load,
      facts_dir: ENV.fetch('FACTS_DIR', 'facts'),
      gem_index: -> { Tools::GemIndex.new(token: ENV.fetch('PUPPET_FORGE_TOKEN', nil)) },
    ).call
  end

  def output_lines(result)
    {
      'version' => result.version.to_s,
      'agent_major' => result.agent_major.to_s,
      'agent' => result.agent.to_s,
      'agents' => JSON.generate(result.agents || {}),
      'map_changed' => result.map_changed ? 'true' : 'false',
      'matrix' => JSON.generate(result.matrix || { 'include' => [] }),
      'selected_ids' => JSON.generate(result.selected_ids),
    }.map { |key, value| "#{key}=#{value}\n" }
  end

  def summary(result)
    return "> [!WARNING]\n> #{result.noop_reason}\n" if result.noop?

    "### Gather plan\n\n- Facter: #{result.version}\n- puppet-agent: #{result.agent}\n" \
      "- Platforms: #{result.selected_ids.size}\n- Map update needed: #{result.map_changed}\n"
  end

  def append(path, text)
    File.open(path, 'a') { |file| file.write(text) }
  end

  def publish(result)
    lines = output_lines(result)
    if ENV['GITHUB_OUTPUT'].to_s.empty?
      puts lines
    else
      append(ENV.fetch('GITHUB_OUTPUT'), lines.join)
    end
    append(ENV.fetch('GITHUB_STEP_SUMMARY'), summary(result)) unless ENV['GITHUB_STEP_SUMMARY'].to_s.empty?
  end
end

namespace :gather do
  desc 'Resolve the Facter version and platform matrix for a gather run'
  task :plan do
    GatherTasks.publish(GatherTasks.plan_from_env)
  rescue ArgumentError, GatherTasks::Tools::VersionMap::UnknownVersion, GatherTasks::Tools::GemIndex::Error => e
    abort e.message
  end
end

namespace :platforms do
  desc 'Check config/platforms.yml schema and Puppet Core supported-OS coverage'
  task :check do
    platforms = GatherTasks.platforms
    problems = platforms.errors
    problems += platforms.coverage_gaps.map do |triple|
      "#{triple}: Core supported OS neither gathered nor skipped in config/platforms.yml"
    end
    problems.each { |problem| warn problem }
    abort "#{problems.size} platform config problem(s)" unless problems.empty?

    puts "#{platforms.entries.size} platform(s): #{platforms.active.size} active, #{platforms.skipped.size} skipped"
  end
end
