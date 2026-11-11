# frozen_string_literal: true

require 'net/http'

# Lists released facter gem versions from the Puppet Core gem index.
# The endpoint shape (rubygems.org v1 versions JSON) is unverified until the
# 03-07 spike; HOST and PATH are the single place to change.
class Puppetlabs::FacterDB::Tools::GemIndex
  HOST = 'rubygems-puppetcore.puppet.com'
  PATH = '/api/v1/versions/facter.json'
  USER = 'forge-key'
  TIMEOUT = { open_timeout: 15, read_timeout: 30 }.freeze

  class Error < StandardError; end

  def initialize(token:, http: Net::HTTP)
    raise ArgumentError, 'PUPPET_FORGE_TOKEN is not set' if token.nil? || token.empty?

    @token = token
    @http = http
  end

  def versions
    entries = JSON.parse(fetch)
    entries.select { |e| e['platform'] == 'ruby' && e['prerelease'] == false }
           .map { |e| e['number'].to_s }
           .grep(Puppetlabs::FacterDB::Tools::VersionMap::VERSION)
           .uniq
           .sort_by { |v| Gem::Version.new(v) }
  rescue JSON::ParserError
    raise Error, 'gem index returned a malformed response'
  end

  def inspect
    "#<#{self.class.name}>"
  end

  private

  def fetch
    request = Net::HTTP::Get.new(PATH)
    request.basic_auth(USER, @token)
    response = @http.start(HOST, 443, use_ssl: true, **TIMEOUT) { |session| session.request(request) }
    raise Error, "gem index request failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPOK)

    response.body.to_s
  end
end
