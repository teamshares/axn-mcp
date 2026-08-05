# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

desc "Run all checks (specs + RuboCop) — the release gate"
task verify: %i[spec rubocop]

task default: :verify

# Gate `rake release` on `verify`, the same way axn core does. bundler/gem_tasks' `release` task
# depends on `build`, so enhancing `build` with `verify` runs specs + RuboCop before the gem is even
# built — and therefore before the tag / RubyGems push steps. A failing check aborts the release
# before anything is tagged or pushed.
Rake::Task["build"].enhance([:verify])
