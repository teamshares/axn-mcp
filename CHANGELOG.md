# Changelog

## 0.2.0

First published release. `Axn::MCP` exposes plain [Axn](https://github.com/teamshares/axn) actions as
[Model Context Protocol](https://modelcontextprotocol.io/) tools — author an action once and expose
it over MCP (and, via sibling adapters like `axn-ruby_llm`, elsewhere) without rewriting it.

### Exposing tools

- **`Axn::MCP.wrap(axn_class, description: nil, name: nil, title: nil, icons: nil, meta: nil, annotations: nil, present_as: nil)`**
  turns any plain Axn (`include Axn`) into an `::MCP::Tool` subclass whose `.call` returns an
  `MCP::Tool::Response`. The original Axn is untouched — a direct `.call` still returns an
  `Axn::Result` — so the same class can be exposed to other adapters too. `description:` defaults to
  the Axn's own `.description`; `name:` to axn core's `tool_name` (honoring a `tool name:` /
  `tool mcp: { name: }` override and `tool_name_stripped_prefixes`). Raises if a truly anonymous Axn
  is wrapped without `name:`.
- **`Axn::MCP.tools`** — zero-arg; returns every Axn registered for the `:mcp` adapter, already
  wrapped and deterministically ordered by tool name, for `MCP::Server.new(tools: Axn::MCP.tools)`.
  Symmetric with `Axn::RubyLLM.tools`.
- **Membership.** An Axn is a `:mcp` tool if its file lives under a configured `tool_roots` directory
  (default `["agent_tools"]` — shared with `axn-ruby_llm`, so a tool dropped in `app/agent_tools/` is
  exposed on both surfaces), or it declares `tool :mcp` / `tool mcp: { … }`, or it carries a
  `configure(:mcp)` block. `tool` is additive; `tool false` / `tool except: :mcp` opt out — net
  membership is `(directory grant ∪ declaration) − except`. `Axn::MCP.config.tool_roots` is
  broad-path-validated (a root of `app`/`.`/`actions`/a `..` traversal is rejected). Per-adapter tool
  config can be declared inline via `tool mcp: { … }`.
- **One-off inline tools** — no bespoke factory; compose
  `Axn::MCP.wrap(Axn::Factory.build(expects:, exposes:) { … }, name: "…")`.
- Wrapped tools mix freely with hand-written `::MCP::Tool`s in the same `MCP::Server` `tools:` array.

### Schemas & serialization

- `inputSchema` / `outputSchema` and exposed-value serialization come from axn core reflection
  (`Axn::Reflection::Schema` / `Axn::Reflection::Values`) — covering `expects`/`exposes` types,
  `inclusion:` enums, `model:` `_id` fields, `coerce:`, subfields, and `of:` / `shape:` typed array
  elements. Nullable/optional fields reflect as a `type` array (`["string", "null"]`); a
  conditionally-required field (`expects :token, if: :use_token`) reflects as an `allOf` clause so
  `MCP::Server`'s pre-flight check doesn't wrongly reject a valid call. Reflection is best-effort and
  deliberately biased stricter-than-runtime (see the README for the one documented looser case).
- `on: :ambient_context` fields are excluded from `inputSchema`.

### Server context & ambient data

- `Axn::MCP.wrap` spreads the injected `server_context` **as** the Axn's `ambient_context`, so a tool
  declares the data it needs generically — `expects :user_id, on: :ambient_context` — and the same
  class resolves it from the MCP server context, from `Current` on a direct call, or from another
  adapter, with no MCP-specific intermediate. axn extracts each declared field via `#[]`/`#dig` (so a
  `Hash` or an `MCP::ServerContext` object both work), and the explicit ambient context replaces any
  process-wide `Current`-derived default (no server-side leakage).
- **`Axn::MCP.server_context`** exposes the live `MCP::ServerContext` for transport capabilities
  (`report_progress`, `cancelled?`) inside a wrapped call — `nil` otherwise — scoped via
  `ActiveSupport::IsolatedExecutionState` (thread/fiber per the configured isolation level).

### Annotations, metadata & response text

- A class's `semantic_hints` (`:read_only` / `:idempotent` / `:destructive`, plus MCP-only
  `:open_world` / `:closed_world` registered by this gem) drive MCP annotations by default; an
  explicit `annotations:` wins.
- `title` / `icons` / `meta` / `annotations` are settable as `wrap` kwargs or declaratively via
  `configure(:mcp)` (so they survive the zero-arg `Axn::MCP.tools` path); a `wrap` kwarg wins.
- **`present_as`** (`:structured` | `:message`) chooses whether the response text block is the
  serialized `exposes` or the Axn's message (`structuredContent` always carries the exposed data).
  Settable gem-wide (`Axn::MCP.config.present_as`), per-class (`configure(:mcp)`), or on `wrap`.
- Failures surface the Axn's own `result.error` — no gem-imposed headline; declare a per-tool base
  `error "…"` for a friendlier generic message (it prefixes an explicit `fail!("reason")` unless
  `standalone: true`).

### Configuration

- Config uses axn core's `Axn::Configurable` DSL under `config_namespace :mcp`, so a base Axn can be
  configured for this gem and another adapter (e.g. `axn-ruby_llm`) independently on the same class.

### Dependency

- Tracks `axn` git `main` (`github: "teamshares/axn", branch: "main"`) — this release needs axn core
  reflection, tool-registry, ambient-context, and namespaced-config primitives that have no tagged
  axn release yet. `Gemfile.lock` is gitignored; `bundle update axn` to advance.
