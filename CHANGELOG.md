# Changelog

## 0.2.0

Re-architected around **author-once**: write a plain Axn and expose it as an `::MCP::Tool` with
`Axn::MCP.wrap` (one tool) or `Axn::MCP.tools` (every registered `:mcp` tool). The `Axn::MCP::Tool`
subclass base is retired, and schema generation + value serialization now come from `axn` core
reflection rather than gem code.

### Added

- `Axn::MCP.wrap(axn_class, description: nil, name: nil, title: nil, icons: nil, meta: nil, annotations: nil, present_as: nil)` —
  expose any plain Axn (`include Axn`) as an `::MCP::Tool` subclass whose `.call` always returns an
  `MCP::Tool::Response`. The original Axn is untouched (direct `.call` still returns `Axn::Result`).
  `description:` defaults to the Axn's own `.description`; `name:` to axn core's canonical `tool_name`
  (honors a `tool name:` override + `tool_name_stripped_prefixes`); annotations derive from the Axn's
  `semantic_hints` unless an explicit `annotations:` is passed. Raises if a truly anonymous Axn (no
  class name, no `axn_name`) is wrapped without `name:`.
- `Axn::MCP.tools` — zero-arg convenience returning every Axn registered as a `:mcp` tool (via
  `tool :mcp`, a `configure(:mcp)` bag, or residency under a configured `tool_path`), each already
  wrapped and deterministically ordered by `tool_name`. `MCP::Server.new(tools: Axn::MCP.tools)`.
  Symmetric with `Axn::RubyLLM.tools`.
- Registers `:mcp` as a tool adapter with axn core's process-global registry
  (`Axn.register_tool_adapter(:mcp)`), backing `Axn.tools_for(:mcp)`.
- `present_as` (`:structured` | `:message`) — picks whether a tool's response text block is the
  serialized `exposes` or the Axn's success/error message. Settable gem-wide
  (`Axn::MCP.config.present_as`), per-class (`configure(:mcp) { |c| c.present_as = … }`), or on
  `Axn::MCP.wrap(present_as:)` (most-local wins). `:structured` is the default; `structuredContent`
  always carries the exposed data regardless.
- `open_world` / `closed_world` registered as MCP-only `semantic_hints`. A class's `semantic_hints`
  (`:read_only` / `:idempotent` / `:destructive` / `:open_world` / `:closed_world`) drive its MCP
  annotations by default; an explicit `annotations:` on `wrap` always wins.
- `title:` / `icons:` / `meta:` kwargs on `Axn::MCP.wrap` (mirroring `::MCP::Tool`'s own class methods).

### Changed

- **Schemas and serialization come from `axn` core** (`Axn::Reflection::Schema` /
  `Axn::Reflection::Values`), replacing the gem's own builder. Consumer-visible reflection
  differences: nullable/optional fields reflect as a `type` array (`["string", "null"]`) rather than
  a bare type; boolean fields gain `enum: [true]`/`[false]`; a `model:` field's generated `_id` no
  longer asserts `type: "integer"` (a primary key's type isn't statically knowable) but forbids
  `null` when required; every `exposes` field is listed in output `required` (optionality shows up as
  a nullable `type`); a `Numeric` field's output type is omitted (it admits `Complex`); and a
  `shape:` block on an `Array` field with no `of:` is no longer reflected in the *output* schema
  (combine `shape:` with `of:` for typed output items — input schema is unaffected).
- **`server_context` is routed through axn core's `ambient_context`** (`expects :server_context, on:
  :ambient_context, type: Object`) — excluded from `inputSchema`, and an explicit `server_context:`
  fully replaces any process-wide `Current`-derived context (no server-side state leaks into an MCP
  call). Read it with `&.dig(...)`: its runtime class varies (a plain `Hash` resolves to an
  `ActiveSupport::HashWithIndifferentAccess`; a real `MCP::Server` round-trip passes an
  `MCP::ServerContext`), so don't assert a specific class.
- **MCP error responses carry the Axn's own `result.error`** (axn's `"Something went wrong"` for a
  bare `fail!` / validation error / unhandled exception, or the explicit `fail!` reason). Declare a
  per-tool base `error "…"` for a friendlier generic message.
- Config is declared with axn core's `Axn::Configurable` DSL under `config_namespace :mcp`, so a base
  Axn composes cleanly with other adapters' per-class config (`configure(:mcp)` /
  `configure(:other_adapter)`) on the same class.

### Removed (breaking)

- **`Axn::MCP::Tool` subclass base** — author a plain Axn + `Axn::MCP.wrap` instead. Its dual-mode
  `.call` (returning `Axn::Result` *or* `MCP::Tool::Response` depending on a `server_context:` kwarg)
  overrode `input_schema` to a non-Hash `MCP::Tool::InputSchema`, which broke `Axn::RubyLLM.wrap` on
  the same class. Kept as a raising tombstone with a migration message (deletion at 1.0 — see
  `DEPRECATIONS.md`).
- **`Axn::MCP::Tool.define`** — build a one-off inline tool with
  `Axn::MCP.wrap(Axn::Factory.build(…) { … }, name: "…")`. Also a raising tombstone.
- **`Axn::MCP.wrap(mcp_text_content:)` kwarg** — renamed to `present_as:`. Kept as a raising alias
  with a pointed migration error (removed at 1.0). The `mcp_text_content` config setting was renamed
  to `present_as` (hard rename; nothing released).
- **`Axn::MCP.config.error_headline`** — the gem no longer imposes a `"Tool call failed"` headline
  (see the error-response change above).
- **Annotation bang-methods** (`read_only!` / `destructive!` / `idempotent!` / `open_world!` /
  `closed_world!`) and the `open_world` / `closed_world` class helpers — declare `semantic_hints` on
  the plain Axn instead.
- **`resolved_mcp_text_content`** — read `SomeTool.present_as` (axn core also dropped the
  `resolved_<name>` reader form in PRO-2888).

### Fixed

- Conditionally-required fields (`expects :token, if: :use_token`) reflect as an `allOf` conditional
  clause instead of an unconditional `required` entry, so `MCP::Server`'s pre-flight
  `missing_required_arguments?` check no longer rejects a valid call that omits the gated field.

### Documentation

- README re-oriented to author-once (`wrap` / `.tools`, inline `Factory.build` recipe, mixing with
  native `MCP::Tool` tools). New "Divergences from the raw MCP SDK" section documents the two
  intentionally-unmapped `MCP::Tool::Response` output affordances (non-text content, response-level
  `_meta`). Documents that schema reflection is best-effort and biased stricter-than-runtime (naming
  the one looser-than-runtime case — a field with an invalid literal default), that the gem is scoped
  to MCP Tools only, and `MCP::ServerContext`'s richer session capabilities (`report_progress`,
  `cancelled?`).

### Dependency

- Tracks `axn` git `main` (`github: "teamshares/axn", branch: "main"`) — this release needs axn core
  primitives (PRO-2842 / 2875 / 2878 / 2880 / 2881 / 2888 / 2921) that have no tagged axn release
  yet. `Gemfile.lock` is gitignored; `bundle update axn` to advance.

## 0.1.1

- Migrated internal configuration off hand-rolled code onto the upstream `Axn::Configurable` DSL (added in axn PRO-2769). The public surface is unchanged: `Axn::MCP.config.mcp_text_content`, per-tool `mcp_text_content(...)` overrides, and `resolved_mcp_text_content` all behave as before.
- `Axn::MCP::Tool` now declares a base error headline, default `"Tool call failed"` (leveraging axn's error-prefix feature). Failures with no explicit reason — validation errors, unexpected exceptions, bare `fail!` — now surface as the headline alone instead of axn's generic `"Something went wrong"`, and explicit reasons are contextualized as `"<headline>: <reason>"`. The headline is a proper `Axn::MCP.config.error_headline` setting (String, non-blank), resolved fresh on every failure — set it gem-wide with no reload or require-order caveat. Subclasses can still override with their own base `error "..."`, which wins over the configured headline, or opt a single message out with `fail!("...", standalone: true)`. The headline presentation is uniform across `call` and `call!`: a failing `call!` raises an `Axn::Failure` whose `#message` matches `result.error` (e.g. `"Tool call failed: <reason>"`).
- Requires an `axn` version that ships `Axn::Configurable`, base-`error` prefixing, and the `standalone:` message flag (axn PRO-2746 / PRO-2820 / PRO-2832).

## 0.1.0

- Initial release
- `Axn::MCP::Tool` base class for building MCP tools with Axn
- Auto-generated JSON schemas from `expects`/`exposes` declarations
- Automatic `model:` field handling (exposes `_id` field to LLM)
- Auto-serialization of exposed values to JSON-safe structures
- Annotation shortcuts: `read_only!`, `destructive!`, `idempotent!`, `open_world!`, `closed_world!`
- Factory-style `Tool.define` for quick one-off tools
- Dual-use: returns `Axn::Result` for direct calls, `MCP::Tool::Response` when called via MCP server
- Typed array element schemas: `Array` fields with `of:` emit a machine-readable `items:` entry in JSON Schema rather than a bare `array` type — scalar types, `:boolean`/`:uuid` shorthands, `Data.define` structs (bare member names), and union types (`anyOf`) are all supported
- Structured field contracts via `shape:` block: annotate individual element/member types and validations inline; `required` is derived automatically from optional vs non-optional members; blocks recurse for nested objects
- When `of: <Data.define>` and a `shape:` block are combined, Data members provide the bare-name baseline and block-declared members overlay typed properties (enrich)
