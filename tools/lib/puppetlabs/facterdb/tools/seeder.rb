# frozen_string_literal: true

require 'date'
require 'digest'
require 'fileutils'

class Puppetlabs::FacterDB::Tools::Seeder
  VERSION = %r{\A(\d+)\.(\d+)\.(\d+)\z}
  Candidate = Struct.new(:source_path, :data, :version, :dir, :basename)

  Report = Puppetlabs::FacterDB::Tools::SeedReport

  def initialize(source:, dest:, config:, normaliser:, today: Date.today)
    @source = File.expand_path(source)
    @dest = File.expand_path(dest)
    @config = config
    @normaliser = normaliser
    @today = today
  end

  def run
    info = source_info
    @report = Report.new
    @winners = {}
    Dir.glob('facts/*/*.facts', base: @source).sort.each { |rel| consider(rel) }
    @winners.each { |rel, cand| write_winner(rel, cand) }
    write_provenance(info)
    @report
  end

  private

  def source_info
    Puppetlabs::FacterDB::Tools::SourceInfo.new(@source).to_h
  end

  def skip(rel, reason)
    @report.skipped << { 'source_path' => rel, 'reason' => reason }
    nil
  end

  def consider(rel)
    data = JSON.parse(File.binread(File.join(@source, rel)).force_encoding(Encoding::UTF_8))
    match = data.is_a?(Hash) && data['facterversion'].is_a?(String) && VERSION.match(data['facterversion'])
    return skip(rel, 'missing or malformed facterversion') unless match

    reason = @config.seed_skip_reason(match)
    return skip(rel, reason) if reason

    admit(rel, data, match)
  rescue JSON::ParserError
    skip(rel, 'invalid JSON')
  end

  def admit(rel, data, match)
    basename = File.basename(rel)
    target = @config.renames.fetch(basename, basename)
    return skip(rel, 'filename does not follow <os>-<release>-<arch>.facts') unless filename_valid?(target)

    @report.renamed << { 'source_path' => rel, 'target' => target } if target != basename
    compete(Candidate.new(rel, data, Gem::Version.new(match[0]), "#{match[1].to_i}.#{match[2].to_i}", target))
  end

  def compete(cand)
    key = File.join(cand.dir, cand.basename)
    current = @winners[key]
    if current.nil?
      @winners[key] = cand
    elsif cand.version > current.version
      lose(current, cand)
      @winners[key] = cand
    else
      lose(cand, current)
    end
  end

  def filename_valid?(name)
    Puppetlabs::FacterDB::Tools::Validator.filename_valid?(name, @config.rolling_distros)
  end

  def lose(loser, winner)
    @report.superseded << { 'source_path' => loser.source_path, 'version' => loser.version.to_s, 'by' => winner.version.to_s }
  end

  def target_path(rel)
    path = File.expand_path(File.join(@dest, rel))
    raise ArgumentError, "refusing to write outside dest: #{rel}" unless path.start_with?(@dest + File::SEPARATOR)

    path
  end

  def write_winner(rel, cand)
    path = target_path(rel)
    existing = existing_version(path)
    return keep(rel, cand, existing) if existing && existing > cand.version

    content = @normaliser.render(cand.data)
    write_if_changed(path, content)
    @report.seeded << seeded_entry(rel, cand, content)
  end

  def keep(rel, cand, existing)
    @report.kept << { 'path' => rel, 'version' => existing.to_s, 'source_version' => cand.version.to_s, 'source_path' => cand.source_path }
  end

  def seeded_entry(rel, cand, content)
    { 'path' => rel, 'facterversion' => cand.version.to_s, 'source_path' => cand.source_path, 'sha256' => Digest::SHA256.hexdigest(content) }
  end

  def existing_version(path)
    return nil unless File.file?(path)

    data = JSON.parse(File.binread(path))
    version = data['facterversion'] if data.is_a?(Hash)
    VERSION.match?(version.to_s) ? Gem::Version.new(version) : nil
  rescue JSON::ParserError
    nil
  end

  def write_if_changed(path, content)
    return if File.file?(path) && File.binread(path) == content.b

    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
    @report.changed = true
  end

  def write_provenance(info)
    provenance = Puppetlabs::FacterDB::Tools::Provenance
    manifest = provenance.manifest(@report, info, @config, @today)
    provenance.write(@dest, manifest) unless provenance.current?(@dest, manifest)
  end
end
