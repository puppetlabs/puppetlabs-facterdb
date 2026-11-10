# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Config
  attr_reader :scrub_policy, :rolling_distros, :seed_major, :seed_min_minor, :seed_max_minor, :renames

  def self.load(root = Puppetlabs::FacterDB::Tools::REPO_ROOT)
    scrub_path = File.join(root, 'config', 'scrub.yml')
    facts_path = File.join(root, 'config', 'facts.yml')
    new(scrub_path, YAML.safe_load_file(scrub_path), facts_path, YAML.safe_load_file(facts_path))
  end

  def self.fetch(hash, key, path)
    raise ArgumentError, "#{path}: missing required key '#{key}'" unless hash.is_a?(Hash) && hash.key?(key)

    hash[key]
  end

  def initialize(scrub_path, scrub, facts_path, facts)
    @scrub_policy = self.class.fetch(scrub, 'scrub', scrub_path).transform_keys(&:to_s)
    @rolling_distros = Array(self.class.fetch(facts, 'rolling_distros', facts_path)).map(&:to_s)
    @renames = self.class.fetch(facts, 'renames', facts_path).to_h { |k, v| [k.to_s, v.to_s] }
    load_seed(self.class.fetch(facts, 'seed', facts_path), facts_path)
  end

  def seed_skip_reason(match)
    major = match[1].to_i
    return "OpenFact-numbered facterversion #{match[0]} (5.x+)" if major > @seed_major
    return "pre-4.x facterversion #{match[0]}" if major < @seed_major
    return nil if (@seed_min_minor..@seed_max_minor).cover?(match[2].to_i)

    "facterversion #{match[0]} outside seed range #{seed_range}"
  end

  def seed_range
    "#{@seed_major}.#{@seed_min_minor}-#{@seed_major}.#{@seed_max_minor}"
  end

  private

  def load_seed(seed, path)
    @seed_major, @seed_min_minor, @seed_max_minor = ['major', 'min_minor', 'max_minor'].map do |key|
      Integer(self.class.fetch(seed, key, path))
    end
  end
end
