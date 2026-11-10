# frozen_string_literal: true

require 'open3'
require 'uri'

class Puppetlabs::FacterDB::Tools::SourceInfo
  def initialize(source)
    @source = source
  end

  def to_h
    commit = git('rev-parse', 'HEAD')
    raise ArgumentError, "source is not a git checkout: #{File.basename(@source)}" unless commit

    { 'repo' => remote_url, 'commit' => commit, 'dirty' => !git('status', '--porcelain').to_s.empty? }
  end

  private

  def git(*args)
    out, status = Open3.capture2e('git', '-C', @source, *args)
    status.success? ? out.strip : nil
  end

  def remote_url
    url = git('config', '--get', 'remote.origin.url')
    return File.basename(@source) if url.nil? || url.empty?

    uri = URI.parse(url)
    uri.user = nil
    uri.password = nil
    uri.to_s
  rescue URI::Error
    File.basename(@source)
  end
end
