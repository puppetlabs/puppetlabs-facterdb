# frozen_string_literal: true

require 'json'
require_relative '../facterdb'

class Puppetlabs::FacterDB::Bin
  def initialize(args)
    @args = args
  end

  # An unquoted multi-word filter arrives as several arguments, so join them.
  def run
    facts = Puppetlabs::FacterDB.get_facts(@args.join(' '))
    # Older json versions pretty-print an empty array as "[\n\n]"
    puts facts.empty? ? '[]' : JSON.pretty_generate(facts)
  rescue RuntimeError, SystemCallError, JSON::ParserError => e
    warn "puppetlabs-facterdb: #{e.message}"
    exit 1
  end
end
