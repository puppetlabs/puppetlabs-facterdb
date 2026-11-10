# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'puppetlabs/facterdb/tools'

module FactsTasks
  Tools = Puppetlabs::FacterDB::Tools

  module_function

  def config
    @config ||= Tools::Config.load
  end

  def normaliser
    Tools::Normaliser.new(Tools::Scrubber.new(config.scrub_policy))
  end

  def validator
    Tools::Validator.new(config: config, scrubber: Tools::Scrubber.new(config.scrub_policy), normaliser: normaliser)
  end

  def facts_dir
    ENV.fetch('FACTS_DIR', 'facts')
  end

  def check_mode?
    !ENV.fetch('CHECK', '').empty? && ENV.fetch('CHECK', '') != '0'
  end

  def report_errors(root)
    errors = validator.validate(root)
    errors.each { |e| warn "#{e.path}: #{e.message}" }
    errors.size
  end

  def normalise_file(path)
    data = JSON.parse(File.binread(path).force_encoding(Encoding::UTF_8))
    content = normaliser.render(data)
    return :unchanged if File.binread(path) == content.b

    File.binwrite(path, content) unless check_mode?
    :changed
  rescue JSON::ParserError => e
    warn "#{path}: invalid JSON: #{e.message}"
    :invalid
  end
end

namespace :facts do
  desc 'Validate fact files (JSON, facterversion/dir, filename, normalised form, scrub leaks)'
  task :validate do
    root = FactsTasks.facts_dir
    count = FactsTasks.validator.files(root).size
    abort "no fact files found under #{root}" if count.zero?

    failures = FactsTasks.report_errors(root)
    abort "#{failures} fact file error(s)" if failures.positive?

    puts "#{count} fact file(s) valid"
  end

  desc 'Scrub and normalise fact files in place (CHECK=1 reports only)'
  task :normalise do
    results = FactsTasks.validator.files(FactsTasks.facts_dir).to_h { |path| [path, FactsTasks.normalise_file(path)] }
    changed = results.select { |_, r| r == :changed }.keys
    verb = FactsTasks.check_mode? ? 'would change' : 'normalised'
    changed.each { |path| puts "#{verb}: #{path}" }
    abort 'fact files need normalising' if FactsTasks.check_mode? && !changed.empty?
    abort 'invalid fact files found' if results.value?(:invalid)

    puts "#{changed.size} fact file(s) #{verb}"
  end

  desc 'Seed Facter 4.0-4.11 facts from a facterdb-private checkout: rake "facts:seed[/path/to/facterdb-private]"'
  task :seed, [:source] do |_, args|
    abort 'usage: rake "facts:seed[/path/to/facterdb-private]"' if args[:source].to_s.empty?

    dest = File.join(Puppetlabs::FacterDB::Tools::REPO_ROOT, 'facts')
    seeder = Puppetlabs::FacterDB::Tools::Seeder.new(source: args[:source], dest: dest, config: FactsTasks.config, normaliser: FactsTasks.normaliser)
    puts seeder.run
    failures = FactsTasks.report_errors(dest)
    abort "#{failures} fact file error(s) after seeding" if failures.positive?
  end
end
