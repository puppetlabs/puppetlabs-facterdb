# frozen_string_literal: true

require 'jgrep'
require 'json'
require_relative 'facterdb/version'

module Perforce::FacterDB::Errors; end
class Perforce::FacterDB::Errors::InvalidFilter < RuntimeError; end

module Perforce::FacterDB
  # @return [String] returns a giant incomprehensible string of concatenated json data
  def self.database
    @database ||= "[#{facterdb_fact_files.map { |f| read_json_file(f) }.join(',')}]\n"
  end

  # @note Call this method at the end of test suite, for example via after(:suite), to reclaim back the memory required to hold json data and filter cache
  def self.cleanup
    @database = nil
    Thread.current[:perforce_facterdb_last_filter_seen] = nil
    Thread.current[:perforce_facterdb_last_facts_seen] = nil
  end

  # @return [Boolean] returns true if we should use the default facterdb database, false otherwise
  # @note If the user passes anything to the PERFORCE_FACTERDB_SKIP_DEFAULTDB environment variable we assume
  # they want to skip the default db
  def self.use_defaultdb?
    ENV['PERFORCE_FACTERDB_SKIP_DEFAULTDB'].nil?
  end

  # @return [Boolean] returns true if we should inject the source file name and file path into the json factsets.
  # The default is false.
  def self.inject_source?
    !ENV['PERFORCE_FACTERDB_INJECT_SOURCE'].nil?
  end

  def self.read_json_file(f) # rubocop:disable Naming/MethodParameterName
    content = File.read(f)
    return content unless inject_source?

    # Find the opening brace
    first_brace = content.index('{')
    return content if first_brace.nil?

    # Inject source file information
    json_injection = "\"_facterdb_filename\": #{File.basename(f).to_json}, "
    json_injection += "\"_facterdb_path\": #{File.expand_path(f).to_json}, "
    content.insert(first_brace + 1, json_injection)
  end
  private_class_method :read_json_file

  # @return [Array[String]] list of all files found in the default facterdb facts path
  def self.default_fact_files
    return [] unless use_defaultdb?

    facts_dir = File.expand_path('../../facts', __dir__)
    Dir.glob(File.join(facts_dir, '**', '*.facts'))
  end

  # @return [Array[String]] list of all files found in the user supplied facterdb facts path
  # @param fact_paths [String] a path-separator delimited list of paths to search for fact files
  # @note nonexistent directories are skipped silently
  def self.external_fact_files(fact_paths = ENV.fetch('PERFORCE_FACTERDB_SEARCH_EXTERNAL_DIR', nil))
    fact_paths ||= ''
    return [] if fact_paths.empty?

    paths = fact_paths.split(File::PATH_SEPARATOR).filter_map do |fact_path|
      fact_path = fact_path.gsub(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
      fact_path = fact_path.strip
      next unless File.directory?(fact_path)

      File.join(fact_path, '**', '*.facts')
    end
    Dir.glob(paths)
  end

  # @return [Array[String]] list of all files found in the default facterdb facts path and user supplied path
  # @note external fact files supplied by the user will take precedence over default fact files found in this gem
  def self.facterdb_fact_files
    (external_fact_files + default_fact_files).uniq
  end

  # @return [String] the string filter
  # @param filter [Object] The filter to convert to jgrep string
  def self.generate_filter_str(filter = nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
    case filter
    when ::Array
      "(#{filter.map { |f| f.map { |k, v| "#{k}=#{v}" }.join(' and ') }.join(') or (')})"
    when ::Hash
      filter.map { |k, v| "#{k}=#{v}" }.join(' and ')
    when ::String
      filter
    when ::NilClass
      ''
    else
      raise Errors::InvalidFilter, "filter must be either an Array a Hash, String, or nil, received #{filter.class}"
    end
  end

  # @return [Boolean] true if the filter is valid against the jgrep filter validator
  # @param filters [Object] The filter to convert to jgrep string
  def self.valid_filters?(filters)
    filter_str = generate_filter_str(filters)
    JGrep.validate_filters(filter_str).nil?
  rescue RuntimeError
    false
  end

  # @return [Array[Hash[Symbol, Any]]] array of hashes of facts
  # @param filter [Object] The filter to convert to jgrep string
  # @param symbolize_keys [Boolean]
  #   Whether to symbolize the keys. Note this is only on the top level and not
  #   on nested values.
  def self.get_facts(filter = nil, cache = true, symbolize_keys: true) # rubocop:disable Metrics/CyclomaticComplexity, Style/OptionalBooleanParameter
    return Thread.current[:perforce_facterdb_last_facts_seen] if cache && filter && filter == Thread.current[:perforce_facterdb_last_filter_seen]

    filter_str = generate_filter_str(filter)
    result = JGrep.jgrep(database, filter_str)
    result = result.map { |hash| hash.transform_keys(&:to_sym) } if symbolize_keys
    if cache
      Thread.current[:perforce_facterdb_last_filter_seen] = filter
      Thread.current[:perforce_facterdb_last_facts_seen] = result
    end
    result
  end
end
