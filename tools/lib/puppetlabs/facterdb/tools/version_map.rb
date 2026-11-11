# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::VersionMap
  VERSION = %r{\A\d+\.\d+\.\d+\z}
  MAJOR = %r{\A\d+\z}
  MIN_VERSION = Gem::Version.new('4.12.0')
  HEADER = <<~YAML
    # Facter version -> Puppet Core puppet-agent version, per agent major.
    #
    # Source of truth is the Facter release notes page (Puppet Core versions):
    # https://help.puppet.com/core/current/Content/PuppetCore/FacterReleaseNotes/release_notes_facter.htm
    # Entries are edited manually or added by the scheduled gather run. The agent
    # version equals the Puppet Core version listed on the page unless the Core
    # packages show otherwise. Where a Facter version ships in several agent
    # majors the newest major is used for gathering.
  YAML

  Resolution = Struct.new(:facter, :agent_major, :agent, keyword_init: true)

  class UnknownVersion < StandardError; end

  def self.load(path = File.join(Puppetlabs::FacterDB::Tools::REPO_ROOT, 'config', 'facter_versions.yml'))
    new(path, YAML.safe_load_file(path))
  end

  def initialize(path, data)
    versions = Puppetlabs::FacterDB::Tools::Config.fetch(data, 'versions', path)
    @map = {}
    (versions || {}).each { |version, agents| store(version.to_s, agents) }
  end

  def include?(version)
    @map.key?(version)
  end

  def agents_for(version)
    @map.fetch(version) { raise UnknownVersion, "no puppet-agent mapping for Facter #{version}" }
  end

  def resolve(version)
    agents = agents_for(version)
    major = agents.keys.max_by(&:to_i)
    Resolution.new(facter: version, agent_major: major, agent: agents[major])
  end

  def add(version, agents)
    normalised = validate(version, agents)
    return false if @map[version] == normalised

    @map[version] = normalised
    true
  end

  def versions
    @map.keys.sort_by { |v| Gem::Version.new(v) }
  end

  def dump
    body = versions.map do |version|
      lines = @map[version].sort_by { |major, _| major.to_i }.map { |major, agent| "    '#{major}': '#{agent}'" }
      "  '#{version}':\n#{lines.join("\n")}\n"
    end
    "#{HEADER}\nversions:\n#{body.join}"
  end

  def write(path)
    File.write(path, dump)
  end

  private

  def store(version, agents)
    @map[version] = validate(version, agents)
  end

  def validate(version, agents)
    check(version, VERSION, 'Facter version')
    raise ArgumentError, "no agents given for Facter #{version}" unless agents.is_a?(Hash) && !agents.empty?

    agents.to_h { |major, agent| [check(major, MAJOR, 'agent major'), check(agent, VERSION, 'agent version')] }
  end

  def check(value, pattern, label)
    raise ArgumentError, "malformed #{label}: #{value.inspect}" unless value.to_s.match?(pattern)

    value.to_s
  end
end
