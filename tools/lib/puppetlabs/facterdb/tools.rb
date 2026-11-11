# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative '../../../../lib/puppetlabs/facterdb/version'

module Puppetlabs::FacterDB::Tools
  REPO_ROOT = File.expand_path('../../../..', __dir__)
end

require_relative 'tools/config'
require_relative 'tools/scrubber'
require_relative 'tools/normaliser'
require_relative 'tools/validator'
require_relative 'tools/facter_versions'
require_relative 'tools/release_notes'
