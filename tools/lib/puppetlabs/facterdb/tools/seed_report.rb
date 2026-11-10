# frozen_string_literal: true

Puppetlabs::FacterDB::Tools::SeedReport = Struct.new(:seeded, :renamed, :skipped, :superseded, :kept, :changed) do
  def initialize
    super([], [], [], [], [], false)
  end

  def to_s
    lines = ["Seeded: #{seeded.size}"] + sections
    lines << (changed ? 'Wrote changes' : 'No changes')
    "#{lines.join("\n")}\n"
  end

  private

  # [title, field, formatter]
  def titles
    [
      ['Renamed:', :renamed, ->(e) { "#{e['source_path']} -> #{e['target']}" }],
      ['Skipped:', :skipped, ->(e) { "#{e['source_path']}: #{e['reason']}" }],
      ['Superseded:', :superseded, ->(e) { "#{e['source_path']} (#{e['version']}) by #{e['by']}" }],
      ['Kept:', :kept, ->(e) { "#{e['path']} (#{e['version']} kept over source #{e['source_version']})" }],
    ]
  end

  def sections
    titles.flat_map { |title, field, fmt| section(title, public_send(field), &fmt) }
  end

  def section(title, entries, &)
    entries.empty? ? [] : [title] + entries.map { |e| "  #{yield(e)}" }
  end
end
