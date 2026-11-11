# frozen_string_literal: true

# Decides what a gather run covers: validates dispatch input (D-16, D-17) or
# detects the oldest unseen Core Facter release on schedule (D-15, D-15a, D-15b).
class Puppetlabs::FacterDB::Tools::GatherPlan
  Result = Struct.new(:version, :agent_major, :agent, :agents, :map_changed, :matrix, :selected_ids, :noop_reason, keyword_init: true) do
    def noop?
      version.nil?
    end
  end

  NO_NEW_RELEASE = 'No new Facter release'

  def self.stored_versions(facts_dir)
    stored = {}
    Dir.glob(File.join(facts_dir, '*', '*.facts')).each do |path|
      version = facterversion(path)
      next if version.nil?

      minor = File.basename(File.dirname(path))
      stored[minor] = version if stored[minor].nil? || Gem::Version.new(version) > Gem::Version.new(stored[minor])
    end
    stored
  end

  def self.facterversion(path)
    version = JSON.parse(File.read(path))['facterversion']
    version if version.is_a?(String) && Puppetlabs::FacterDB::Tools::VersionMap::VERSION.match?(version)
  rescue JSON::ParserError, SystemCallError
    nil
  end

  def self.missing(gem_versions, stored)
    gem_versions.select { |v| candidate?(v, stored) }.sort_by { |v| Gem::Version.new(v) }
  end

  def self.candidate?(version, stored)
    gem = Gem::Version.new(version)
    return false if gem < Puppetlabs::FacterDB::Tools::VersionMap::MIN_VERSION

    current = stored[version.split('.').first(2).join('.')]
    current.nil? || gem > Gem::Version.new(current)
  end

  # rubocop:disable Metrics/ParameterLists
  def initialize(event:, facter_version:, platforms_input:, platforms:, version_map:, facts_dir:, release_notes: nil, gem_index: nil)
    @event = event
    @facter_version = facter_version
    @platforms_input = platforms_input
    @platforms = platforms
    @version_map = version_map
    @facts_dir = facts_dir
    @release_notes = release_notes || -> { Puppetlabs::FacterDB::Tools::ReleaseNotes.fetch }
    @gem_index = gem_index || -> { Puppetlabs::FacterDB::Tools::GemIndex.new(token: ENV.fetch('PUPPET_FORGE_TOKEN', nil)) }
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    case @event
    when 'workflow_dispatch' then dispatch
    when 'schedule' then schedule
    else raise ArgumentError, "unsupported event '#{@event}'"
    end
  end

  private

  def dispatch
    version = validate_version(@facter_version)
    selected = @platforms.select(platform_ids)
    resolved(version, selected)
  end

  def schedule
    version = self.class.missing(@gem_index.call.versions, self.class.stored_versions(@facts_dir)).first
    return noop(NO_NEW_RELEASE) if version.nil?

    resolved(version, @platforms.active) do
      noop("Facter #{version} is not on the release notes page yet (or lists no Puppet Core agent); retrying next run")
    end
  end

  def resolved(version, selected)
    return build(version, @version_map.agents_for(version), false, selected) if @version_map.include?(version)

    agents = @release_notes.call.agents_for(version)
    return yield if agents.empty? && block_given?
    raise ArgumentError, "Facter #{version} is not in config/facter_versions.yml or on the release notes page" if agents.empty?

    build(version, agents, true, selected)
  end

  def build(version, agents, map_changed, selected)
    major = agents.keys.max_by(&:to_i)
    Result.new(
      version: version, agent_major: major, agent: agents[major], agents: agents, map_changed: map_changed,
      matrix: @platforms.matrix(selected), selected_ids: selected.map(&:id)
    )
  end

  def noop(reason)
    Result.new(noop_reason: reason, selected_ids: [], map_changed: false)
  end

  def validate_version(value)
    version = value.to_s
    raise ArgumentError, 'facter_version must be a single X.Y.Z version' unless Puppetlabs::FacterDB::Tools::VersionMap::VERSION.match?(version)
    raise ArgumentError, "facter_version must be >= #{Puppetlabs::FacterDB::Tools::VersionMap::MIN_VERSION}" if Gem::Version.new(version) < Puppetlabs::FacterDB::Tools::VersionMap::MIN_VERSION

    version
  end

  def platform_ids
    @platforms_input.to_s.split(',').map(&:strip).reject(&:empty?)
  end
end
