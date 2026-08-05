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
- Registers `:mcp` as a tool adapter with axn core's process-global registry, passing `Axn::MCP`
  itself as the config source (`Axn::Tools.register_adapter(:mcp, self)`) so the registry reads
  `Axn::MCP.config.tool_roots` for directory-based tool membership. `Axn::MCP` `extend`s
  `Axn::Tools::AdapterRoots` and ships a default `tool_roots` of `["agent_tools"]` — an Axn under
  `app/agent_tools/` is exposed as an MCP tool with no `tool :mcp` declaration, and (since
  `axn-ruby_llm` defaults to the same dir) over ruby_llm too. Roots are broad-path-validated
  (`app`/`.`/`actions`/`..` rejected). Membership is `(directory grant ∪ tool declaration) − except`.
- **Breaking (core, via the axn bump this release requires):** `tool :mcp` now **adds** the adapter
  to the directory grant instead of replacing it (declare all adapters/`name:`/`except:`/per-adapter
  bags in one `tool` call), and the global `Axn.config.tool_paths` is removed in favor of per-adapter
  `<adapter>.config.tool_roots` (for MCP: `Axn::MCP.config.tool_roots`). Per-adapter tool config can
  also be declared inline via `tool mcp: { … }` (sugar over `configure(:mcp)`; axn PRO-2942).
- `present_as` (`:structured` | `:message`) — picks whether a tool's response text block is the
  serialized `exposes` or the Axn's success/error message. Settable gem-wide
  (`Axn::MCP.config.present_as`), per-class (`configure(:mcp) { |c| c.present_as = … }`), or on
  `Axn::MCP.wrap(present_as:)` (most-local wins). `:structured` is the default; `structuredContent`
  always carries the exposed data regardless.
- `reject_opaque_exposed_values` (boolean, default `false`) — when an `exposes` value has no JSON
  rendering its author declared (it would ship as `"#<User:0x…>"`, or an ActiveSupport
  instance-variable dump under Rails), `true` fails the call (error response + `on_exception` report)
  instead of shipping that blob. Settable gem-wide (`Axn::MCP.config.reject_opaque_exposed_values`)
  or per-class (`configure(:mcp)`), per-class wins. Output-side only (not inbound `coerce:`), and
  narrow — values with no *honest* JSON form (cycles, non-finite Floats, non-UTF-8 bytes, colliding
  Hash keys) fail regardless (axn #206 / PRO-2988).
- **`Axn::MCP.wrap(...).call` never raises** — it extends axn's non-bang contract to the transport
  boundary. A transport-layer exception raised *after* the Axn settled (exposed-value serialization,
  response building) is reported via axn's global `on_exception` hook and returned as a generic error
  `MCP::Tool::Response`, rather than escaping to a direct/custom caller. In axn's dev mode
  (`best_effort_raises_in_dev`) it re-raises instead, so real bugs aren't masked.
- `open_world` / `closed_world` registered as MCP-only `semantic_hints`. A class's `semantic_hints`
  (`:read_only` / `:idempotent` / `:destructive` / `:open_world` / `:closed_world`) drive its MCP
  annotations by default; an explicit `annotations:` on `wrap` always wins.
- Per-tool MCP metadata — `title` / `icons` / `meta` / `annotations` — settable either as
  `Axn::MCP.wrap` kwargs or declaratively via `configure(:mcp) { |c| c.title = … }`. The
  `configure(:mcp)` form survives the zero-arg `Axn::MCP.tools` path (which calls `wrap` with no
  kwargs); an explicit `wrap` kwarg wins over it. For `annotations`, precedence is `wrap` kwarg →
  `configure(:mcp)` → `semantic_hints`-derived.
- **Tool versioning (via the axn bump this release requires; axn PRO-2955).** Tool identity is
  `(tool_name, tool_version)`, so `Axn::MCP.tools` exposes only the latest version when several Axns
  share a `tool_name` (`Axn::Tools.for(:mcp)` collapses to the highest `tool_version`). For a
  versioned tool (`tool_version > 1`), `wrap` surfaces the resolved revision as `tool_version` in the
  tool's `_meta` — never in its `name` (the cross-adapter identity). Unversioned tools are unchanged.
- `Axn::MCP::Error` base error class, marked with axn core's `Axn::Error` boundary (axn PRO-2997), so
  a consumer's `rescue Axn::Error` catches this gem's errors alongside core's and the other adapter
  gems'. `Axn::MCP::SchemaError` now subclasses it (still a `StandardError`).

### Changed

- **Schemas and serialization come from `axn` core** — schemas from your `expects`/`exposes`
  declarations and exposed-value rendering via the `Axn::Extensions::Serialization` facade —
  replacing the gem's own builder. Consumer-visible reflection
  differences: nullable/optional fields reflect as a `type` array (`["string", "null"]`) rather than
  a bare type; boolean fields gain `enum: [true]`/`[false]`; a `model:` field's generated `_id` no
  longer asserts `type: "integer"` (a primary key's type isn't statically knowable) but forbids
  `null` when required; every `exposes` field is listed in output `required` (optionality shows up as
  a nullable `type`); a `Numeric` field's output type is omitted (it admits `Complex`); a
  `shape:` block on an `Array` field with no `of:` is no longer reflected in the *output* schema
  (combine `shape:` with `of:` for typed output items — input schema is unaffected); and a required
  `String`/`Array` field reflects axn's non-blank presence validation as `minLength: 1`/`minItems: 1`
  (an optional field is nullable instead, with no minimum).
- **`server_context` is spread into the Axn's `ambient_context`.** `Axn::MCP.wrap` passes the
  injected `server_context` *as* the Axn's `ambient_context` (not nested under a `server_context`
  key), so a tool declares the data it needs directly and generically — `expects :user_id, on:
  :ambient_context` — and stays adapter-agnostic: the *same* class resolves `user_id` from the MCP
  server context, from `Current` on a direct call, or from `Axn::RubyLLM.wrap`, with no MCP-specific
  intermediate. axn extracts each declared field via `#[]`/`#dig`, so it works for a `Hash` or an
  `MCP::ServerContext` object. `on: :ambient_context` fields are excluded from `inputSchema`, and the
  explicit ambient context replaces any process-wide `Current`-derived default (no server-side
  leakage; `nil` on a direct call with none provided).
- **Added `Axn::MCP.server_context`** — the MCP-specific handle for transport *capabilities*
  (`Axn::MCP.server_context.report_progress(...)`, `.cancelled?`), the live `MCP::ServerContext`
  object that doesn't survive `ambient_context`'s declared-key filtering. `nil` outside a wrapped
  tool call. Scoped via `ActiveSupport::IsolatedExecutionState` (thread/fiber per the configured
  isolation level), matching how axn scopes its own per-execution state. Data belongs in
  `ambient_context`; only transport capabilities need this.
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
- **Annotation bang-methods** (`read_only!` / `destructive!` / `idempotent!` / `open_world!` /
  `closed_world!`) — declare `semantic_hints` on the plain Axn instead.

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

### Packaging

- The packaged gem now ships only its runtime surface — `lib/`, `README.md`, `CHANGELOG.md`, and
  `LICENSE`. `spec.files` moved from a denylist to an allowlist (mirroring `axn` core), so
  dev-only artifacts (`AGENTS.md`/`CLAUDE.md`, `DEPRECATIONS.md`, `Rakefile`) that 0.1.0 leaked into
  the package are no longer shipped.

### Dependency

- Requires `axn >= 0.1.0-alpha.5, < 0.2.0` from RubyGems. This release needs axn core's reflection,
  tool-registry, serialization-facade, and namespaced-config primitives, first available in the
  `alpha.5` prerelease. (During development this gem tracked axn `main` from git; now that `alpha.5`
  is published it depends on the released gem.)
- Set the `mcp` requirement to `>= 0.5.0, < 2.0`. Floor is `0.5.0` — the first SDK with the `icons`
  setter and full JSON-Schema tool schemas (so conditional `allOf` survives); `0.4.x` lacks both.
  Upper bound tracks the SDK's semver: `1.0` declared its API stable (breaking only in a future
  major), so the whole `1.x` line is supported. Verified against `mcp` 0.5.0 and 1.1.0.

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
