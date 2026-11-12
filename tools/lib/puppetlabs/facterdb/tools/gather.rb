# frozen_string_literal: true

require 'fileutils'

module Puppetlabs::FacterDB::Tools::Gather
  Result = Struct.new(:placed, :skipped, :invalid)

  IDENTITY = [['os', 'name'], ['os', 'release', 'major'], ['os', 'hardware']].freeze
  ARCH = { 'amd64' => 'x86_64', 'x64' => 'x86_64', 'arm64' => 'aarch64' }.freeze

  module_function

  def validator
    Puppetlabs::FacterDB::Tools::Validator
  end

  def relative_path_for(facts)
    name, major, arch = IDENTITY.map { |keys| fact_string(facts, keys) }
    version = validator::VERSION.match(fact_string(facts, ['facterversion']))
    raise ArgumentError, 'malformed facterversion' unless version

    basename = "#{name.downcase}-#{major}-#{ARCH.fetch(arch.downcase, arch.downcase)}.facts"
    raise ArgumentError, 'os name, release or hardware does not form a valid fact filename' unless validator.filename_valid?(basename, [])

    "#{version[1]}.#{version[2]}/#{basename}"
  end

  def fact_string(facts, keys)
    value = facts.dig(*keys) if facts.is_a?(Hash)
    raise ArgumentError, "missing #{keys.join('.')}" unless value.is_a?(String) && !value.empty?

    value
  end

  def place(src_root, facts_root, version)
    result = Result.new([], [], [])
    Dir.glob('**/*.facts', base: src_root).sort.each do |rel|
      facts = read_facts(File.join(src_root, rel))
      dest = facts && destination(facts, version)
      next result.invalid << rel unless dest

      write_unless_newer(File.join(facts_root, dest), facts, version) ? result.placed << dest : result.skipped << dest
    end
    result
  end

  def write_unless_newer(path, facts, version)
    return false if newer_stored?(path, version)

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(facts))
    true
  end

  def read_facts(path)
    facts = JSON.parse(File.binread(path).force_encoding(Encoding::UTF_8))
    facts.is_a?(Hash) ? facts : nil
  rescue JSON::ParserError
    nil
  end

  def destination(facts, version)
    return nil unless facts['facterversion'] == version

    relative_path_for(facts)
  rescue ArgumentError
    nil
  end

  def newer_stored?(path, version)
    return false unless File.exist?(path)

    stored = read_facts(path)
    return false unless stored && validator::VERSION.match?(stored['facterversion'].to_s)

    Gem::Version.new(stored['facterversion']) > Gem::Version.new(version)
  end

  def summary(labels:, succeeded:, version:, agent:, placed:, skipped:) # rubocop:disable Metrics/ParameterLists
    failed = labels - succeeded
    body = <<~MD
      Facter #{version} facts gathered with Puppet Core agent #{agent}.

      Existing facts are never deleted. The maintainer reviews this PR for leaks and merges by hand. PRs opened with GITHUB_TOKEN do not trigger CI, so run the checks locally or push to re-trigger.

      ## Succeeded legs
      #{list(succeeded)}

      ## Failed legs
      #{list(failed)}

      ## Placed files
      #{list(placed)}

      ## Skipped (newer patch already stored)
      #{list(skipped)}
    MD
    body += "\nLegs failed, so the workflow run stays red until they are re-run.\n" unless failed.empty?
    [body, failed]
  end

  def list(items)
    items.empty? ? '- none' : items.map { |item| "- #{item}" }.join("\n")
  end
end
