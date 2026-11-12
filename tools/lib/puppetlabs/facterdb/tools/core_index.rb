# frozen_string_literal: true

require 'net/http'

class Puppetlabs::FacterDB::Tools::CoreIndex
  BASE_URL = 'https://rubygems-puppetcore.puppet.com'
  PATH = '/info/facter'
  USER = 'forge-key'

  def self.parse(body)
    tokens = version_tokens(body)
    # Tokens with a dash carry a platform suffix; the compact index has none today
    releases = tokens.grep_v(%r{-}).grep(Puppetlabs::FacterDB::Tools::FacterVersions::VERSION)
    raise ArgumentError, 'unexpected Core index response' if releases.empty?

    releases.uniq.sort_by { |v| Gem::Version.new(v) }
  end

  def self.version_tokens(body)
    lines = body.to_s.lines.map(&:strip)
    divider = lines.index('---')
    raise ArgumentError, 'unexpected Core index response' unless divider

    lines.drop(divider + 1).filter_map { |line| line.split(' ', 2).first }
  end
  private_class_method :version_tokens

  def initialize(token: ENV.fetch('PUPPET_FORGE_TOKEN', ''), base_url: BASE_URL)
    raise ArgumentError, 'PUPPET_FORGE_TOKEN is not set' if token.to_s.empty?

    @token = token
    @base_url = base_url
  end

  def facter_versions
    uri = URI("#{@base_url}#{PATH}")
    request = Net::HTTP::Get.new(uri.request_uri)
    request.basic_auth(USER, @token)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 30) { |http| http.request(request) }
    raise "Core index request failed: HTTP #{response.code}" unless response.code == '200'

    self.class.parse(response.body)
  end
end
