require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  t.exclude_pattern = 'spec/integration/dual_install/**/*_spec.rb'
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:rubocop)
rescue LoadError
  # rubocop group not installed
end

import 'tools/tasks/facts.rake'
import 'tools/tasks/gather.rake'

task default: [:spec]
