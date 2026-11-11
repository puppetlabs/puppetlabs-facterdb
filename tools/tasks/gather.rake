# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'puppetlabs/facterdb/tools'

module GatherTasks
  Tools = Puppetlabs::FacterDB::Tools

  module_function

  def platforms
    @platforms ||= Tools::Platforms.load
  end
end

namespace :platforms do
  desc 'Check config/platforms.yml schema and Puppet Core supported-OS coverage'
  task :check do
    platforms = GatherTasks.platforms
    problems = platforms.errors
    problems += platforms.coverage_gaps.map do |triple|
      "#{triple}: Core supported OS neither gathered nor skipped in config/platforms.yml"
    end
    problems.each { |problem| warn problem }
    abort "#{problems.size} platform config problem(s)" unless problems.empty?

    puts "#{platforms.entries.size} platform(s): #{platforms.active.size} active, #{platforms.skipped.size} skipped"
  end
end
