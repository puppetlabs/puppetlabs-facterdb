# frozen_string_literal: true

require 'json'
require_relative '../facterdb'

class Puppetlabs::FacterDB::Bin
  def initialize(args)
    @args = args
  end

  def run
    facts = Puppetlabs::FacterDB.get_facts(@args[0])
    # Older json versions pretty-print an empty array as "[\n\n]"
    puts facts.empty? ? '[]' : JSON.pretty_generate(facts)
  end
end
