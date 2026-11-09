# frozen_string_literal: true

require 'rspec'
require 'puppetlabs/facterdb'

module FixtureHelpers
  def fixtures_dir
    File.expand_path('fixtures/facts', __dir__)
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include FixtureHelpers

  config.around(:each) do |example|
    keys = ENV.keys.grep(%r{\A(PUPPETLABS_)?FACTERDB_})
    saved = ENV.to_h.slice(*keys)
    keys.each { |k| ENV.delete(k) }
    Puppetlabs::FacterDB.cleanup
    begin
      example.run
    ensure
      ENV.keys.grep(%r{\A(PUPPETLABS_)?FACTERDB_}).each { |k| ENV.delete(k) }
      saved.each { |k, v| ENV[k] = v }
      Puppetlabs::FacterDB.cleanup
    end
  end
end
