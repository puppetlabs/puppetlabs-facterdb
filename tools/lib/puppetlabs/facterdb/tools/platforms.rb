# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Platforms
  ID = %r{\A[a-z][a-z0-9]*-[0-9][0-9a-z.]*-[a-z0-9_]+\z}
  FAMILIES = ['linux', 'macos', 'windows'].freeze
  BACKENDS = ['container', 'runner'].freeze

  Entry = Struct.new(:id, :os, :release, :arch, :family, :backend, :runner, :image, :repo_id, :skip, keyword_init: true) do
    def skipped?
      !skip.nil?
    end

    def method_label
      (backend == 'container') ? "container (#{image})" : "runner (#{runner})"
    end

    def filename
      "#{id}.facts"
    end

    def triple
      "#{os}-#{release}-#{arch}"
    end
  end

  attr_reader :entries

  def self.load(root = Puppetlabs::FacterDB::Tools::REPO_ROOT)
    platforms_path = File.join(root, 'config', 'platforms.yml')
    core_path = File.join(root, 'config', 'core_supported_platforms.yml')
    new(platforms_path, YAML.safe_load_file(platforms_path), core_path, YAML.safe_load_file(core_path))
  end

  def initialize(platforms_path, platforms, core_path, core)
    list = Puppetlabs::FacterDB::Tools::Config.fetch(platforms, 'platforms', platforms_path)
    keys = Entry.members.map(&:to_s)
    @entries = Array(list).map { |h| Entry.new(**h.slice(*keys).transform_keys(&:to_sym)) }
    @core = Array(Puppetlabs::FacterDB::Tools::Config.fetch(core, 'core_supported', core_path))
  end

  def find(id)
    entries.find { |e| e.id == id }
  end

  def active
    entries.reject(&:skipped?)
  end

  def skipped
    entries.select(&:skipped?)
  end

  def select(ids)
    return active if Array(ids).empty?

    ids.map { |id| select_one(id.to_s) }
  end

  def matrix(selected)
    rows = selected.map do |e|
      e.to_h.slice(:id, :family, :runner, :image, :repo_id).merge(method: e.method_label).compact.transform_keys(&:to_s)
    end
    { 'include' => rows }
  end

  def errors
    seen = {}
    entries.flat_map { |e| entry_errors(e, seen) }
  end

  def coverage_gaps
    covered = entries.map(&:triple)
    @core.map { |c| c.values_at('os', 'release', 'arch').join('-') }.reject { |t| covered.include?(t) }
  end

  private

  def select_one(id)
    raise ArgumentError, "invalid platform id '#{id}'" unless ID.match?(id)

    entry = find(id)
    raise ArgumentError, "unknown platform id '#{id}'" if entry.nil?
    raise ArgumentError, "platform '#{id}' is skipped: #{entry.skip}" if entry.skipped?

    entry
  end

  def entry_errors(entry, seen)
    label = entry.id.to_s
    errs = []
    errs << "#{label}: duplicate id '#{label}'" if seen[label]
    seen[label] = true
    errs.concat(identity_errors(entry, label))
    errs.concat(skip_errors(entry, label))
    errs.concat(backend_errors(entry, label)) unless entry.skipped?
    errs
  end

  def identity_errors(entry, label)
    errs = []
    errs << "#{label}: id must match #{ID.inspect}" unless ID.match?(label)
    errs << "#{label}: release must be a String (quote it in YAML)" unless entry.release.is_a?(String)
    errs << "#{label}: id must equal '#{entry.triple}'" unless label == entry.triple
    errs << "#{label}: family must be one of #{FAMILIES.join(', ')}" unless FAMILIES.include?(entry.family)
    errs
  end

  def skip_errors(entry, label)
    return [] if entry.skip.nil? || (entry.skip.is_a?(String) && !entry.skip.strip.empty?)

    ["#{label}: skip reason must be a non-empty String"]
  end

  def backend_errors(entry, label)
    errs = []
    errs << "#{label}: backend must be one of #{BACKENDS.join(', ')}" unless BACKENDS.include?(entry.backend)
    errs << "#{label}: container backend requires an image" if entry.backend == 'container' && entry.image.to_s.empty?
    errs + runner_errors(entry, label)
  end

  def runner_errors(entry, label)
    errs = []
    errs << "#{label}: linux entries require repo_id" if entry.family == 'linux' && entry.repo_id.to_s.empty?
    errs << "#{label}: runner is required" if entry.runner.to_s.empty?
    errs << "#{label}: runner must not use a -latest label" if entry.runner.to_s.end_with?('-latest')
    errs
  end
end
