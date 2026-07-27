# AGENTS.md

## Axn-mcp

Author-once model: write a plain Axn (`include Axn`); expose it as an `::MCP::Tool` with
`Axn::MCP.wrap(axn_class, ...)` (one) or `Axn::MCP.tools` (every registered `:mcp` tool —
`Axn.tools_for(:mcp).map { wrap }`). `wrap` returns a `Class.new(::MCP::Tool)` whose `.call` always
returns `MCP::Tool::Response`; the original Axn is untouched (direct `.call` still returns
`Axn::Result`). `server_context:` is routed into the Axn's `ambient_context` by `wrap`/`Invocation`.
Schemas come from axn core reflection (`axn_class.input_schema`/`output_schema`), not gem code.

## Rules

- Expose via `Axn::MCP.wrap`/`Axn::MCP.tools` only. `Axn::MCP::Tool` is a RETIRED raising tombstone
  (`lib/axn/mcp/tool.rb`) — never revive it as a base; it's slated for deletion at 1.0 (see
  `DEPRECATIONS.md`).
- Config is `Axn::Configurable` (`lib/axn/mcp.rb`) — add a `setting`, not a hand-rolled class. Register
  gem-level integrations with core at load: `register_semantic_hint`, and
  `register_tool_adapter(:mcp, self)` (pass `Axn::MCP` as the config source). `Axn::MCP` `extend`s
  `Axn::Tools::AdapterRoots` and ships `tool_roots` default `["agent_tools"]`; membership is
  `(directory-root grant ∪ tool declaration) − except`. There is no `Axn.config.tool_paths`.
- Verify schema output against real `MCP::Tool::Response`/`InputSchema`/`OutputSchema` objects, not
  hand-built hashes (`spec/axn/mcp/tool_spec.rb`, `spec/axn/mcp/wrap_spec.rb`).
- Pin exact user-facing failure/success strings with specs, not `be_present`/`ok?`. The gem imposes
  no error headline — MCP error text is the Axn's own `result.error` (`spec/axn/mcp/serializer_spec.rb`,
  `spec/integration/server_integration_spec.rb`).
- Before touching `fail!`/`error`/`exposes`/`expects`: read axn's `AGENTS-consuming.md`
  (`bundle show axn`) — covers `call`/`call!`, failure buckets, `standalone:`/`join:` prefixing.
- Bumping the `axn` dependency: check its CHANGELOG/PRs for message-presentation shape changes
  before trusting existing specs still assert the right strings. `Gemfile.lock` is gitignored; the
  gem tracks axn `main` via `Gemfile`, `bundle update axn` to advance.
- `bundle exec rspec` + `bundle exec rubocop`. TDD: failing spec first.
- `bin/setup` installs a lefthook pre-commit hook (`lefthook.yml`) that runs RuboCop **check-only**
  on staged `*.{rb,rake,gemspec}` and BLOCKS on any offense — fix and re-stage, it does not
  autocorrect. Skip once with `git commit --no-verify`; CI runs the full `rake` regardless.
- `CHANGELOG.md` entry per user-visible change; bump `lib/axn/mcp/version.rb` per semver.
- Update `README.md` when consumer-visible behavior changes (failure/success text shape, config
  surface, schema output, exposure API). Log retirements/removals in `DEPRECATIONS.md`.
- `spec.files` in the gemspec is an **allowlist** (`lib` + `README`/`CHANGELOG`/`LICENSE`) — new
  root files don't ship unless you add them there. Internal/superpowers notes (plans, specs, drafts)
  go in `internal-docs/` — tracked, never packaged. `docs/` is reserved for a future user-facing
  (VitePress) site; don't put internal notes there.
