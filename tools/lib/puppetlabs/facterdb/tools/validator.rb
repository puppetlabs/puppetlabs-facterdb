# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::Validator
  Error = Struct.new(:path, :message)

  FILENAME = %r{\A(?<os>[a-z][a-z0-9]*)-(?<release>[0-9][0-9a-z.]*(?:-core)?)-(?<arch>[a-z0-9_]+)\.facts\z}
  ROLLING_FILENAME = %r{\A(?<os>[a-z][a-z0-9]*)-(?<arch>[a-z0-9_]+)\.facts\z}
  VERSION = %r{\A(\d+)\.(\d+)\.\d+\z}
  MAJOR_MINOR = %r{\A\d+\.\d+\z}

  def self.filename_valid?(basename, rolling_distros)
    return true if FILENAME.match?(basename)

    match = ROLLING_FILENAME.match(basename)
    !match.nil? && rolling_distros.include?(match[:os])
  end

  def initialize(config:, scrubber:, normaliser:)
    @config = config
    @scrubber = scrubber
    @normaliser = normaliser
  end

  def files(root)
    Dir.glob('**/*.facts', base: root).sort.map { |rel| File.join(root, rel) }
  end

  def validate(root)
    files(root).flat_map do |path|
      rel = path.delete_prefix("#{root}/")
      validate_file(path, rel).map { |message| Error.new(rel, message) }
    end
  end

  private

  def validate_file(path, rel)
    dir = File.dirname(rel)
    errors = layout_errors(dir, File.basename(rel))
    data, parse_error = parse(path)
    return errors + [parse_error] if parse_error

    errors + content_errors(data, dir) + leak_errors(data) + format_errors(path, data)
  end

  def layout_errors(dir, basename)
    errors = []
    errors << "must be in a major.minor directory, found '#{dir}'" unless MAJOR_MINOR.match?(dir)
    errors << "filename '#{basename}' does not match <os>-<release>-<arch>.facts" unless filename_valid?(basename)
    errors
  end

  def filename_valid?(basename)
    self.class.filename_valid?(basename, @config.rolling_distros)
  end

  def parse(path)
    data = JSON.parse(File.binread(path).force_encoding(Encoding::UTF_8))
    data.is_a?(Hash) ? [data, nil] : [nil, 'must be a JSON object']
  rescue JSON::ParserError => e
    [nil, "invalid JSON: #{e.message}"]
  end

  def content_errors(data, dir)
    version = data['facterversion']
    match = version.is_a?(String) && VERSION.match(version)
    return ['missing or malformed facterversion'] unless match
    return [] if "#{match[1]}.#{match[2]}" == dir

    ["facterversion #{version} does not match directory #{dir}"]
  end

  def leak_errors(data)
    @scrubber.leaks(data).map { |leak| "scrub leak at #{leak}: expected placeholder from config/scrub.yml" }
  end

  def format_errors(path, data)
    actual = File.binread(path).force_encoding(Encoding::UTF_8)
    return [] if actual == @normaliser.render(data)

    ['not normalised (run rake facts:normalise)']
  end
end
