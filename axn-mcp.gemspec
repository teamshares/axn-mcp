# frozen_string_literal: true

require_relative "lib/axn/mcp/version"

Gem::Specification.new do |spec|
  spec.name = "axn-mcp"
  spec.version = Axn::MCP::VERSION
  spec.authors = ["Kali Donovan"]
  spec.email = ["kali@teamshares.com"]

  spec.summary = "MCP Tool wrapper for Axn actions"
  spec.description = "Build MCP tools using Axn's expects/exposes contract with auto-generated JSON schemas and responses."
  spec.homepage = "https://github.com/teamshares/axn-mcp"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/teamshares/axn-mcp/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Allowlist, not denylist (mirrors axn core): enumerate the small, stable shippable surface —
  # lib/ plus the user-facing root docs — so dev-only artifacts (AGENTS.md/CLAUDE.md agent
  # instructions, DEPRECATIONS.md, Rakefile, internal-docs/, tool config) can never silently leak
  # into the package as new files land. `git ls-files` keeps it to tracked paths.
  spec.files = IO.popen(
    %w[git ls-files -z --
       lib README.md CHANGELOG.md LICENSE],
    chdir: __dir__, err: IO::NULL,
  ) { |ls| ls.readlines("\x0", chomp: true) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "axn", ">= 0.1.0-alpha.5", "< 0.2.0"
  spec.add_dependency "mcp", ">= 0.5.0", "< 2.0"
end
