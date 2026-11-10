# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Config
  attr_reader :scrub_policy, :rolling_distros

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
  end
end
