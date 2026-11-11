# frozen_string_literal: true

class Puppetlabs::FacterDB::Tools::PrBody
  def self.render(**args)
    new.render(**args)
  end

  def render(version:, agent:, outcomes:, git_status:, run_url:)
    rows = outcomes.map { |o| o.to_h.transform_keys(&:to_sym) }.sort_by { |o| o[:id].to_s }
    [
      "Gathered Facter #{version} facts (puppet-agent #{agent}).",
      "Workflow run: #{run_url}",
      "### Platforms\n\n#{table(rows)}",
      "### Files\n\n#{files(git_status)}",
      '`rake facts:normalise` and `rake facts:validate` passed on the collected files.',
      notes,
    ].join("\n\n") << "\n"
  end

  def table(rows)
    header = ['| Platform | Outcome | Method | Detail |', '| --- | --- | --- | --- |']
    header.concat(rows.map { |o| row(o) }).join("\n")
  end

  def row(outcome)
    detail = [outcome[:action], outcome[:reason]].reject { |v| v.to_s.empty? }.join(': ')
    "| #{[outcome[:id], outcome[:outcome], outcome[:method], detail].map { |v| cell(v) }.join(' | ')} |"
  end

  def cell(value)
    value.to_s.gsub(%r{[[:cntrl:]]}, ' ').gsub('|', '\\|').strip
  end

  def files(git_status)
    added = []
    changed = []
    git_status.to_s.each_line do |line|
      status = line[0, 2].to_s
      path = line[3..].to_s.strip
      next unless path.start_with?('facts/')

      (status.include?('M') ? changed : added) << path if status.match?(%r{[AM?]})
    end
    "Added:\n#{list(added)}\n\nChanged:\n#{list(changed)}"
  end

  def list(paths)
    paths.empty? ? 'None' : paths.sort.map { |p| "- `#{p}`" }.join("\n")
  end

  def notes
    <<~TEXT.strip
      PRs opened by `GITHUB_TOKEN` do not trigger CI. Close and reopen this PR to run the checks.

      Reviewer checklist:
      - [ ] Check the first generated file per OS for identifying data (hostnames, cloud or runner paths, usernames).
    TEXT
  end
end
