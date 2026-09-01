# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# TEMPORARY (PRO-2996): axn's Axn::Tools::AdapterSerialization mixin is merged to main but not yet
# released -- the newest gem is 0.1.0-alpha.5.1. Pull from main to prove the cutover works before
# alpha.6 is cut; revert to the released gem (and raise the gemspec floor to ">= 0.1.0-alpha.6")
# before cutting a new axn-mcp version.
gem "axn", github: "teamshares/axn", branch: "main"

gem "lefthook", "~> 2.0" # Git-hook manager (pre-commit RuboCop on staged files)
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "rubocop", "~> 1.21"
