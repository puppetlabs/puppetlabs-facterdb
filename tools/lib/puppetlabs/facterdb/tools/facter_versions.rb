# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::FacterVersions
  VERSION = %r{\A\d+\.\d+\.\d+\z}
  FLOOR = Gem::Version.new('4.12.0')
  PATH = File.join(Puppetlabs::FacterDB::Tools::REPO_ROOT, 'config', 'facter_versions.yml')
  HEADER = <<~TEXT
    # Facter versions gathered by the automated workflows, mapped to the Puppet Core
    # puppet-agent version they ship with (the newest agent when two exist).
    # Written by `rake versions:update`; hand edits are allowed.
    # Facter 4.0 to 4.11 are seeded and not listed here.
  TEXT

  def self.load(path = PATH)
    data = YAML.safe_load_file(path) || {}
    raise ArgumentError, "#{path}: expected a mapping of Facter version to agent" unless data.is_a?(Hash)

    map = new(path)
    data.each do |version, entry|
      agent = entry.is_a?(Hash) ? entry['agent'] : nil
      raise ArgumentError, "#{path}: invalid entry (version must be X.Y.Z with an X.Y.Z 'agent')" unless version.to_s.match?(VERSION) && agent.to_s.match?(VERSION)

      map.add(version.to_s, agent.to_s)
    end
    map
  end

  def self.stored_version(facts_root, major_minor)
    versions = Dir.glob(File.join(facts_root, major_minor, '*.facts')).map do |file|
      data = begin
        JSON.parse(File.binread(file).force_encoding(Encoding::UTF_8))
      rescue JSON::ParserError
        raise ArgumentError, "#{file}: invalid JSON (details withheld; may contain fact values)"
      end
      Gem::Version.new(data['facterversion'].to_s)
    end
    versions.max
  end

  def self.collection_for(agent)
    "puppetcore#{agent.split('.').first}"
  end

  def initialize(path = PATH)
    @path = path
    @map = {}
  end

  def entries
    @map.sort_by { |version, _| Gem::Version.new(version) }.to_h
  end

  def agent_for(version)
    @map[version]
  end

  def add(version, agent)
    [version, agent].each do |value|
      raise ArgumentError, "#{@path}: invalid version (expected X.Y.Z)" unless value.to_s.match?(VERSION)
    end
    @map[version] = agent
  end

  def render
    return "#{HEADER}{}\n" if @map.empty?

    lines = entries.map { |version, agent| "'#{version}': { agent: '#{agent}' }" }
    "#{HEADER}#{lines.join("\n")}\n"
  end

  def write
    File.write(@path, render)
  end

  def missing(facts_root)
    entries.keys.select do |version|
      stored = self.class.stored_version(facts_root, version.split('.').first(2).join('.'))
      stored.nil? || stored < Gem::Version.new(version)
    end
  end

  def resolve(input, facts_root)
    input = input.to_s
    return missing(facts_root).first if input.empty?

    raise ArgumentError, 'invalid version input (expected X.Y.Z)' unless input.match?(VERSION)
    raise ArgumentError, 'version not found in config/facter_versions.yml' unless @map.key?(input)

    input
  end
end
