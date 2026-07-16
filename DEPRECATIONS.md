# Deprecations & removals

Tracking surface that is deprecated, retired-but-stubbed, or removed — so the dead code is
unambiguously cleaned up before the 1.0 release. When cutting 1.0, everything under
"Retired — stub kept until 1.0" must be deleted.

## Retired — stub kept until 1.0 (DELETE at 1.0)

### `Axn::MCP::Tool` (subclass base) — PRO-2923

Retired in favor of the author-once model: author a plain Axn and expose it with
`Axn::MCP.wrap` (per tool) or `Axn::MCP.tools` (every registered `:mcp` tool). The base's
dual-mode `.call` (returning `Axn::Result` *or* `MCP::Tool::Response` depending on a
`server_context:` kwarg) also overrode `input_schema` to a non-Hash `MCP::Tool::InputSchema`,
which broke `Axn::RubyLLM.wrap` on the same class — the concrete reason it had to go.

Currently kept as a **raising tombstone** (`lib/axn/mcp/tool.rb`): `Class.new(Axn::MCP::Tool)`
and `Axn::MCP::Tool.define(...)` both raise `NotImplementedError` with a migration message,
rather than a bare `NameError`/`NoMethodError`.

**Delete at 1.0:** remove `lib/axn/mcp/tool.rb` and its `require_relative "mcp/tool"` in
`lib/axn/mcp.rb`. Once removed, `Axn::MCP::Tool` is simply undefined.

Migration:

```ruby
# Before
class MyTool < Axn::MCP::Tool
  expects :query, type: String
  exposes :results, type: Array
  def call = expose(results: Item.search(query))
end

# After
class MyTool
  include Axn
  tool :mcp                    # optional: makes it discoverable via Axn::MCP.tools
  expects :query, type: String
  exposes :results, type: Array
  def call = expose(results: Item.search(query))
end

Axn::MCP.wrap(MyTool)          # -> a ready-to-register ::MCP::Tool subclass
```

### `Axn::MCP::Tool.define` (inline factory) — PRO-2923

Removed alongside the base (the raising tombstone above covers it). It was pure sugar over
composing two public primitives; use them directly:

```ruby
Axn::MCP.wrap(
  Axn::Factory.build(expects: { query: { type: String } },
                     exposes: { results: { type: Array } }) { expose results: Item.search(query) },
  name: "search", description: "Search for items",
)
```

## Removed (no stub)

- **`Axn::MCP.config.error_headline`** (PRO-2923) — the gem no longer imposes a `"Tool call
  failed"` headline on failures. MCP error responses now carry the Axn's own `result.error`.
  A tool that wants a generic failure message declares its own axn base `error "..."` (standard
  axn practice), which is per-tool rather than gem-wide.
- **Annotation bang-methods** `read_only!` / `destructive!` / `idempotent!` / `open_world!` /
  `closed_world!`, and the **`open_world` / `closed_world`** class helpers — these lived only on
  the retired `Axn::MCP::Tool` base. Declare `semantic_hints :read_only, :closed_world, ...` on
  the plain Axn instead (axn core registers `:open_world`/`:closed_world` as MCP-specific hints);
  `Axn::MCP.wrap` maps them to MCP annotations, and an explicit `annotations:` kwarg on `wrap`
  still wins.
