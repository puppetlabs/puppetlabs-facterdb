# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'open3'
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

  def map_path
    ENV.fetch('FACTER_VERSIONS_PATH', 'config/facter_versions.yml')
  end

  def selected_ids
    ids = JSON.parse(ENV.fetch('SELECTED_IDS', '[]'))
    raise ArgumentError, 'SELECTED_IDS must be a JSON array of strings' unless ids.is_a?(Array) && ids.all?(String)

    ids
  rescue JSON::ParserError
    raise ArgumentError, 'SELECTED_IDS must be a JSON array of strings'
  end

  def collect
    version = ENV.fetch('FACTER_VERSION')
    store = Tools::Store.new(platforms: platforms, facts_dir: ENV.fetch('FACTS_DIR', 'facts'), version: version)
    outcomes = store.place(ENV.fetch('ARTIFACTS_DIR'), selected_ids, unfiltered: ENV['UNFILTERED'] == 'true')
    File.write(ENV.fetch('REPORT_PATH'), JSON.pretty_generate(outcomes.map { |o| o.to_h.compact }))
    outcomes.each { |o| puts "#{o.id} #{o.outcome} #{o.action}".strip }
    append(ENV.fetch('GITHUB_OUTPUT'), "failed=#{store.failed?(outcomes)}\n") unless ENV['GITHUB_OUTPUT'].to_s.empty?
  end

  def run_url
    server = ENV.fetch('GITHUB_SERVER_URL', 'https://github.com')
    "#{server}/#{ENV.fetch('GITHUB_REPOSITORY', '')}/actions/runs/#{ENV.fetch('GITHUB_RUN_ID', '')}"
  end

  def pr_body
    status, = Open3.capture2('git', 'status', '--porcelain', '--', 'facts')
    body = Tools::PrBody.render(
      version: ENV.fetch('FACTER_VERSION'), agent: ENV.fetch('AGENT_VERSION'),
      outcomes: JSON.parse(File.read(ENV.fetch('REPORT_PATH'))), git_status: status, run_url: run_url
    )
    File.write(ENV.fetch('PR_BODY_PATH'), body)
  end

  def update_map
    map = Tools::VersionMap.load(map_path)
    version = ENV.fetch('FACTER_VERSION')
    agents = (map.include?(version) ? map.agents_for(version) : {}).merge(ENV.fetch('AGENT_MAJOR') => ENV.fetch('AGENT_VERSION'))
    changed = map.add(version, agents)
    map.write(map_path) if changed
    puts(changed ? 'updated' : 'unchanged')
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

  desc 'Write the resolved Facter to puppet-agent mapping into config/facter_versions.yml'
  task :update_map do
    GatherTasks.update_map
  rescue ArgumentError => e
    abort e.message
  end

  desc 'Place gathered leg artifacts into facts/ and write the outcomes report'
  task :collect do
    GatherTasks.collect
  rescue ArgumentError, KeyError => e
    abort e.message
  end

  desc 'Render the facts PR body from the collect report'
  task :pr_body do
    GatherTasks.pr_body
  rescue KeyError, JSON::ParserError, SystemCallError => e
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
