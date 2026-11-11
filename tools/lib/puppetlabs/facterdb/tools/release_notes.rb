# frozen_string_literal: true

require 'net/http'
require 'uri'

class Puppetlabs::FacterDB::Tools::ReleaseNotes
  URL = 'https://help.puppet.com/core/current/Content/PuppetCore/FacterReleaseNotes/release_notes_facter.htm'
  ALLOWED_HOST = 'help.puppet.com'
  MAX_REDIRECTS = 3
  LEAD_LENGTH = 300
  CORE = 'Puppet Core'
  TIMEOUT = 15
  VERSION = %r{\d+\.\d+\.\d+}
  HEADING = %r{Facter\s+(\d+)\.(\d+)\.\s*(\d+)}
  ENTITIES = { '&nbsp;' => ' ', '&amp;' => '&', '&lt;' => '<', '&gt;' => '>', '&quot;' => '"', '&#39;' => "'" }.freeze

  def self.fetch(url = URL)
    uri = https_uri(url)
    (MAX_REDIRECTS + 1).times do
      response = get(uri)
      return parse(response.body.to_s) if response.is_a?(Net::HTTPOK)
      raise "release notes fetch failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPRedirection)

      uri = https_uri(response['location'].to_s, host: ALLOWED_HOST)
    end
    raise ArgumentError, 'too many redirects fetching release notes'
  end

  def self.https_uri(url, host: nil)
    uri = URI.parse(url)
    raise ArgumentError, "release notes URL must be https: #{url}" unless uri.is_a?(URI::HTTPS)
    raise ArgumentError, "refusing redirect to #{uri.host}" if host && uri.host != host

    uri
  end

  def self.get(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.get(uri.request_uri)
    end
  end

  def self.parse(html)
    new(html)
  end

  def initialize(html)
    @core = {}
    sections(text_of(html)).each do |version, body|
      found = core_sentence_versions(body)
      @core[version] = found unless found.empty?
    end
  end

  def versions
    @core.keys
  end

  def core_versions(version)
    @core.fetch(version, [])
  end

  def agents_for(version)
    core_versions(version).group_by { |v| v.split('.').first }.transform_values do |list|
      list.max_by { |v| Gem::Version.new(v) }
    end
  end

  private

  def text_of(html)
    text = html.gsub(%r{<(script|style)\b.*?</\1>}mi, ' ').gsub(%r{<[^>]*>}m, ' ')
    ENTITIES.each { |entity, char| text = text.gsub(entity, char) }
    text.gsub(%r{\s+}, ' ')
  end

  def sections(text)
    matches = text.to_enum(:scan, HEADING).map { Regexp.last_match }
    matches.each_with_index.map do |m, i|
      stop = matches[i + 1] ? matches[i + 1].begin(0) : text.length
      ["#{m[1]}.#{m[2]}.#{m[3]}", text[m.end(0)...stop]]
    end
  end

  def core_sentence_versions(body)
    start = body[0, LEAD_LENGTH].index(CORE)
    return [] unless start

    body[(start + CORE.length)..][%r{\A.*?(?:\.(?:\s|\z)|\z)}m].scan(VERSION)
  end
end
