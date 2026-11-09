# frozen_string_literal: true

require 'json'
require_relative '../facterdb'

class Puppetlabs::FacterDB::Bin
  def initialize(args)
    @args = args
  end

  def run
    puts JSON.pretty_generate(Puppetlabs::FacterDB.get_facts(@args[0]))
  end
end
