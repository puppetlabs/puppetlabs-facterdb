# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Store
  Outcome = Struct.new(:id, :outcome, :reason, :method, :path, :action, keyword_init: true) # rubocop:disable Lint/StructNewOverride

  RESULT_OUTCOMES = ['gathered', 'skipped', 'failed'].freeze
  REASON_LIMIT = 200

  def initialize(platforms:, facts_dir:, version:)
    @platforms = platforms
    @facts_dir = facts_dir
    @version = version
  end

  # One Outcome per selected id, plus config-skipped entries when the run was unfiltered.
  def place(artifacts_dir, selected_ids, unfiltered: false)
    outcomes = selected_ids.grep(Puppetlabs::FacterDB::Tools::Platforms::ID).map do |id|
      place_one(artifacts_dir, id)
    end
    outcomes + (unfiltered ? config_skipped : [])
  end

  def failed?(outcomes)
    outcomes.any? { |o| o.outcome == 'failed' }
  end

  private

  def config_skipped
    @platforms.skipped.map do |entry|
      Outcome.new(id: entry.id, outcome: 'skipped', reason: clean(entry.skip), method: entry.method_label)
    end
  end

  def place_one(artifacts_dir, id)
    entry = @platforms.find(id)
    return failed(id, nil, 'unknown platform id') if entry.nil?

    dir = File.join(artifacts_dir, "gather-#{id}")
    place_result(id, entry.method_label, dir, read_json(File.join(dir, 'result.json')))
  end

  def place_result(id, method, dir, result)
    return failed(id, method, 'no result artifact') if result.nil?
    return failed(id, method, 'invalid result outcome') unless RESULT_OUTCOMES.include?(result['outcome'])
    return place_facts(id, method, read_json(File.join(dir, 'facts.json'))) if result['outcome'] == 'gathered'

    Outcome.new(id: id, outcome: result['outcome'], reason: clean(result['reason']), method: method)
  end

  def place_facts(id, method, data)
    return failed(id, method, 'invalid facts JSON') unless data.is_a?(Hash)
    return failed(id, method, 'facterversion mismatch') unless data['facterversion'] == @version

    computed = computed_id(data)
    return failed(id, method, "identity mismatch: facts describe '#{computed}'") unless computed == id

    write(id, method, data)
  end

  def computed_id(data)
    os = data['os'].is_a?(Hash) ? data['os'] : {}
    release = os['release'].is_a?(Hash) ? os['release'] : {}
    [os['name'].to_s.downcase, release['major'], os['hardware']].join('-').gsub(%r{[^a-z0-9._-]}i, '?')
  end

  def write(id, method, data)
    major, minor, = @version.split('.')
    path = File.join(@facts_dir, "#{major}.#{minor}", "#{id}.facts")
    action = File.exist?(path) ? 'changed' : 'added'
    return gathered(id, method, path, 'kept_newer') if action == 'changed' && stored_newer?(path)

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(data))
    gathered(id, method, path, action)
  end

  def stored_newer?(path)
    stored = read_json(path)&.dig('facterversion')
    Gem::Version.new(stored) > Gem::Version.new(@version)
  rescue ArgumentError, TypeError
    false
  end

  def gathered(id, method, path, action)
    Outcome.new(id: id, outcome: 'gathered', reason: '', method: method, path: path, action: action)
  end

  def failed(id, method, reason)
    Outcome.new(id: id, outcome: 'failed', reason: reason, method: method)
  end

  def read_json(path)
    return nil unless File.file?(path)

    JSON.parse(File.binread(path).force_encoding(Encoding::UTF_8))
  rescue JSON::ParserError
    nil
  end

  def clean(text)
    text.to_s.gsub(%r{[[:cntrl:]]}, ' ')[0, REASON_LIMIT].strip
  end
end
