# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'json'

module Puppetlabs::FacterDB::Tools::Provenance
  module_function

  def manifest(report, source_info, config, today = Date.today)
    {
      'source_repo' => source_info['repo'],
      'source_commit' => source_info['commit'],
      'source_dirty' => source_info['dirty'],
      'seeded_on' => today.iso8601,
      'facter_range' => config.seed_range,
      'counts' => counts(report),
    }.merge(entries(report))
  end

  def entries(report)
    { 'files' => report.seeded, 'renamed' => report.renamed, 'skipped' => report.skipped, 'superseded' => report.superseded, 'kept' => report.kept }
  end

  def write(dest, manifest)
    FileUtils.mkdir_p(dest)
    File.binwrite(File.join(dest, 'seed-manifest.json'), Puppetlabs::FacterDB::Tools::Normaliser.format(manifest))
    File.binwrite(File.join(dest, 'PROVENANCE.md'), markdown(manifest))
  end

  # True when both provenance files exist and match the manifest, ignoring seeded_on.
  def current?(dest, manifest)
    path = File.join(dest, 'seed-manifest.json')
    return false unless File.file?(path) && File.file?(File.join(dest, 'PROVENANCE.md'))

    existing = JSON.parse(File.binread(path))
    existing.is_a?(Hash) && existing.except('seeded_on') == JSON.parse(JSON.generate(manifest)).except('seeded_on')
  rescue JSON::ParserError
    false
  end

  def counts(report)
    ['seeded', 'renamed', 'skipped', 'superseded', 'kept'].to_h { |k| [k, report.public_send(k).size] }
  end

  def markdown(manifest)
    lines = header(manifest) + counts_table(manifest['counts']) + lists(manifest) + footer
    "#{lines.join("\n")}\n"
  end

  def lists(manifest)
    list('Renamed', manifest['renamed']) { |e| "`#{e['source_path']}` -> `#{e['target']}`" } +
      list('Skipped', manifest['skipped']) { |e| "`#{e['source_path']}`: #{e['reason']}" }
  end

  def header(manifest)
    [
      '# Fact data provenance',
      '',
      "The fact files under `facts/` were seeded by `rake facts:seed` from `#{manifest['source_repo']}` " \
      "at commit `#{manifest['source_commit']}` on #{manifest['seeded_on']}.",
      "Facter range: #{manifest['facter_range']}. Source checkout had uncommitted changes: #{manifest['source_dirty'] ? 'yes' : 'no'}.",
      '',
    ]
  end

  def counts_table(counts)
    ['| Result | Files |', '| --- | --- |'] + counts.map { |k, v| "| #{k} | #{v} |" } + ['']
  end

  def list(title, entries, &)
    return [] if entries.empty?

    ["## #{title}", ''] + entries.map { |e| "- #{yield(e)}" } + ['']
  end

  def footer
    [
      '## Notes',
      '',
      'Fact JSON is never annotated; provenance lives only in this file and `seed-manifest.json`. ' \
      'Fact files are scrubbed per `config/scrub.yml` and normalised before they are written.',
      '',
    ] + attribution
  end

  def attribution
    [
      '## Attribution',
      '',
      'This data derives from [voxpupuli/facterdb](https://github.com/voxpupuli/facterdb) (Apache-2.0) ' \
      "via Puppet's fork puppetlabs/facterdb-private. See [NOTICE](../NOTICE).",
    ]
  end
end
