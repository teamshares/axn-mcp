# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "lefthook", "~> 2.0" # Git-hook manager (pre-commit RuboCop on staged files)
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "rubocop", "~> 1.21"

# TEMP (PRO-3587): the residue-description spec needs `input_schema_residues`, which is on axn main but
# unreleased (main still reports 0.1.0-alpha.6.1, a version string RubyGems already has without it).
# Pinned by ref because Gemfile.lock is gitignored. Before cutting a version of this gem: raise the
# gemspec axn floor to the release that ships residues and drop this pin.
gem "axn", git: "https://github.com/teamshares/axn", ref: "9e2a143d302c7801b8f0b13578fc8540705a3998"
