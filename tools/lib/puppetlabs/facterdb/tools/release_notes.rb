# frozen_string_literal: true

require 'cgi'
require 'net/http'

class Puppetlabs::FacterDB::Tools::ReleaseNotes
  URL = 'https://help.puppet.com/core/current/Content/PuppetCore/FacterReleaseNotes/release_notes_facter.htm'
  MissingVersion = Class.new(StandardError)

  def self.fetch(url = URL)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 30) do |http|
      http.get(uri.request_uri)
    end
    raise "release notes fetch failed: HTTP #{response.code}" unless response.code == '200'

    response.body
  end

  def self.parse(html)
    new(html).versions
  end

  def initialize(html)
    @versions = extract(html)
  end

  attr_reader :versions

  def agent_for!(version)
    @versions.fetch(version) { raise MissingVersion, "no Puppet Core agent found in the release notes for Facter #{version}" }
  end

  private

  def extract(html)
    text = CGI.unescapeHTML(html.to_s.gsub(%r{<[^>]*>}, ' ')).gsub(%r{\s+}, ' ')
    text = text.gsub(%r{(\d+\.\d+)\.\s+(\d+)}, '\1.\2')
    sections(text).each_with_object({}) do |(version, section), result|
      agent = newest_agent(section)
      result[version] = agent if agent && !result.key?(version)
    end
  end

  def sections(text)
    marks = text.to_enum(:scan, %r{Facter (\d+\.\d+\.\d+)}).map { [Regexp.last_match(1), Regexp.last_match.begin(0)] }
    marks.each_with_index.map do |(version, start), index|
      [version, text[start...(marks[index + 1]&.last || text.length)]]
    end
  end

  def newest_agent(section)
    clause = section[%r{Puppet Core.*?(?:\.\s|\.?\z)}m]
    return nil unless clause

    clause.scan(%r{\d+\.\d+\.\d+}).max_by { |v| Gem::Version.new(v) }
  end
end
