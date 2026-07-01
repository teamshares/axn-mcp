# AGENTS.md

## Axn-mcp

`Axn::MCP::Tool` wraps an Axn action so `Tool.call` dual-serves: with `server_context:` it returns
`MCP::Tool::Response`; without it, `Axn::Result`. Schemas (`lib/axn/mcp/schema_builder.rb`)
generate from `expects`/`exposes`.

## Rules

- Never break the `server_context:`-presence branch in `Tool.call` (`lib/axn/mcp/tool.rb`).
- Config is `Axn::Configurable` (`lib/axn/mcp.rb`) — add a `setting`, not a hand-rolled class.
- Verify schema output against real `MCP::Tool::Response`/`InputSchema`/`OutputSchema` objects, not
  hand-built hashes (`spec/axn/mcp/schema_builder_spec.rb`).
- Pin exact user-facing failure/success strings with specs, not `be_present`/`ok?`
  (`spec/axn/mcp/base_error_spec.rb`).
- Before touching `fail!`/`error`/`exposes`/`expects`: read axn's `AGENTS-consuming.md`
  (`bundle show axn`) — covers `call`/`call!`, failure buckets, `standalone:`/`join:` prefixing.
- Bumping the `axn` dependency: check its CHANGELOG/PRs for message-presentation shape changes
  before trusting existing specs still assert the right strings.
- `bundle exec rspec` + `bundle exec rubocop`. TDD: failing spec first.
- `CHANGELOG.md` entry per user-visible change; bump `lib/axn/mcp/version.rb` per semver.
- Update `README.md` when consumer-visible behavior changes (failure/success text shape, config
  surface, schema output).
