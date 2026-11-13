# frozen_string_literal: true

require 'fileutils'

module Puppetlabs::FacterDB::Tools::Gather # rubocop:disable Metrics/ModuleLength
  Result = Struct.new(:placed, :skipped, :invalid)
  CommandError = Class.new(StandardError)

  IDENTITY = [['os', 'name'], ['os', 'release', 'major'], ['os', 'hardware']].freeze
  ARCH = { 'amd64' => 'x86_64', 'x64' => 'x86_64', 'arm64' => 'aarch64' }.freeze

  RESULT_FILE = 'result.json'
  STATUSES = ['success', 'skipped', 'failed'].freeze
  REASON_TEXT = {
    'agent_unavailable' => 'no agent package for this OS',
    'provision_failed' => 'provision service error',
    'other' => 'other failure',
    'no_result' => 'no result recorded',
    'facts_missing' => 'facts artifact missing',
  }.freeze
  AGENT_UNAVAILABLE = [
    %r{No match for argument: puppet-agent-\d},
    %r{Package puppet-agent is not available},
    %r{Unable to retrieve a valid package},
    %r{ERROR 404},
  ].freeze
  PROVISION_FAILED = [
    %r{provision service returned an error},
    %r{provisioning of .* failed},
  ].freeze

  module_function

  def validator
    Puppetlabs::FacterDB::Tools::Validator
  end

  # Litmus run_shell raises with the full output on failure, so always opt out and report the exit code only.
  def run_command(runner, command)
    result = runner.run_shell(command, expect_failures: true)
    code = result.exit_code
    raise CommandError, "#{command} failed with exit code #{code.inspect} (details withheld)" unless code.is_a?(Integer) && code.zero?

    result.stdout.to_s
  end

  # Classifies a litmus failure message by category only; the message itself must never be returned or logged.
  def classify_failure(message)
    text = message.to_s
    return :provision_failed if PROVISION_FAILED.any? { |pattern| text.match?(pattern) }
    return :agent_unavailable if AGENT_UNAVAILABLE.any? { |pattern| text.match?(pattern) }

    :other
  end

  def write_result(dir, label, status, reason = nil)
    raise ArgumentError, 'invalid result status' unless STATUSES.include?(status)

    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, RESULT_FILE), JSON.generate('label' => label, 'status' => status, 'reason' => reason&.to_s))
  end

  # Maps each label to its recorded result; a missing or unreadable file counts as failed.
  def read_results(root, labels)
    labels.to_h { |label| [label, read_result(File.join(root, "result-#{label}", RESULT_FILE))] }
  end

  # A leg that reports success must also have delivered facts; a lost artifact would otherwise look like a clean run.
  def require_facts(results, gathered)
    results.to_h do |label, result|
      delivered = Dir.glob('**/*.facts', base: File.join(gathered, "facts-#{label}")).any?
      missing = result['status'] == 'success' && !delivered
      [label, missing ? { 'status' => 'failed', 'reason' => 'facts_missing' } : result]
    end
  end

  def read_result(path)
    data = JSON.parse(File.read(path))
    status = data['status'] if data.is_a?(Hash)
    return { 'status' => status, 'reason' => data['reason'] } if STATUSES.include?(status)

    { 'status' => 'failed', 'reason' => 'no_result' }
  rescue SystemCallError, JSON::ParserError
    { 'status' => 'failed', 'reason' => 'no_result' }
  end

  def relative_path_for(facts)
    name, major, arch = IDENTITY.map { |keys| fact_string(facts, keys) }
    version = validator::VERSION.match(fact_string(facts, ['facterversion']))
    raise ArgumentError, 'malformed facterversion' unless version

    basename = "#{name.downcase}-#{major}-#{ARCH.fetch(arch.downcase, arch.downcase)}.facts"
    raise ArgumentError, 'os name, release or hardware does not form a valid fact filename' unless validator.filename_valid?(basename, [])

    "#{version[1]}.#{version[2]}/#{basename}"
  end

  def render_scrubbed(facts, config = Puppetlabs::FacterDB::Tools::Config.load)
    tools = Puppetlabs::FacterDB::Tools
    tools::Normaliser.new(tools::Scrubber.new(config.scrub_policy)).render(facts)
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

  def summary(labels:, results:, version:, agent:, placed:, skipped:) # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize
    by_status = ->(status) { labels.select { |label| results.dig(label, 'status') == status } }
    succeeded = by_status.call('success')
    unavailable = by_status.call('skipped')
    failed = labels - succeeded - unavailable
    body = <<~MD
      Facter #{version} facts gathered with Puppet Core agent #{agent}. The agent is derived from the [Facter release notes](#{Puppetlabs::FacterDB::Tools::ReleaseNotes::URL}).

      Existing facts are never deleted. The maintainer reviews this PR for leaks and merges by hand. PRs opened with GITHUB_TOKEN do not trigger CI, so run the checks locally or push to re-trigger.

      ## Succeeded legs
      #{list(succeeded)}

      ## Skipped (no agent package for this OS)
      #{list(unavailable.map { |label| "#{label}: #{reason_text(results.dig(label, 'reason') || 'agent_unavailable')}" })}

      ## Failed legs
      #{list(failed.map { |label| "#{label}: #{reason_text(results.dig(label, 'reason') || 'no_result')}" })}

      ## Placed files
      #{list(placed)}

      ## Skipped (newer patch already stored)
      #{list(skipped)}
    MD
    body += "\nLegs failed, so the workflow run stays red until they are re-run.\n" unless failed.empty?
    [body, failed]
  end

  def reason_text(reason)
    REASON_TEXT.fetch(reason.to_s, REASON_TEXT['other'])
  end

  def list(items)
    items.empty? ? '- none' : items.map { |item| "- #{item}" }.join("\n")
  end
end
