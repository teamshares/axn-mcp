# AGENTS.md

Guidance for agents working **on** axn-mcp — the Axn wrapper for MCP tools. Read before writing code.
(This is the sibling of axn's own `AGENTS.md`, which guides agents working on axn itself.)

## What this gem does

Wraps `Axn::MCP::Tool` (an Axn action) so it dual-serves: called with `server_context:` it returns
`MCP::Tool::Response`; called without it, it returns a plain `Axn::Result`. Schemas
(`lib/axn/mcp/schema_builder.rb`) are generated from `expects`/`exposes`, not hand-written.

## Non-negotiables

- **Never break the dual-use branch** in `Tool.call` (`lib/axn/mcp/tool.rb`) — presence of
  `server_context:` is the only signal that decides `Axn::Result` vs `MCP::Tool::Response`.
- **Reuse Axn's DSL; don't re-implement it.** Config lives in `Axn::Configurable`
  (`lib/axn/mcp.rb`), not a hand-rolled class. A new cross-cutting knob is a `setting`, not a new
  ad-hoc mechanism.
- **Schema output must stay spec-accurate.** Verify against real `MCP::Tool::Response` /
  `InputSchema`/`OutputSchema` objects, not hand-built hashes — see `spec/axn/mcp/schema_builder_spec.rb`
  for the pattern.
- **Pin exact user-facing strings with specs**, not just `be_present`/`ok?`. The failure headline
  (`error "Tool call failed"` in `tool.rb`) and success text are what an LLM actually reads — see
  `spec/axn/mcp/base_error_spec.rb` for the pattern (every failure mode, exact string, no awkward
  joins).

## Before touching `fail!`/`error`/`exposes`/`expects` usage

Read axn's in-gem agent guide first: run `bundle show axn` and read `AGENTS-consuming.md` at that
path. It covers the contract surface, `call` vs `call!` semantics, the failure-bucket model
(`fail!` vs `fails_on` vs unhandled exception), base/reason message prefixing (`standalone:`,
`join:`), and the gotchas. This gem's own base error headline and `call!` parity behavior build
directly on that model — get it wrong here and every downstream tool's error text is wrong.

## Testing

- `bundle exec rspec` and `bundle exec rubocop` before calling anything done.
- TDD: failing spec first, then implementation.
- When bumping the `axn` dependency, check axn's CHANGELOG/PRs for message-presentation churn
  (`prefixed:`/`standalone:`/`join:` have all changed shape across alpha) before assuming existing
  specs still assert the right strings — run the full suite and read the diffs, don't just trust green.

## Changes & compatibility

- `CHANGELOG.md` entry for every user-visible change; bump `lib/axn/mcp/version.rb` per semver.
- `README.md` is the public usage doc — update it whenever behavior visible to gem consumers
  changes (e.g. the shape of failure/success text, config surface, schema output).
