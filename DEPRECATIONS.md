# Deprecations & removals

Tracking surface that is deprecated, retired-but-stubbed, or removed — so the dead code is
unambiguously cleaned up before the 1.0 release. When cutting 1.0, everything under
"Retired — stub kept until 1.0" must be deleted.

## Retired — stub kept until 1.0 (DELETE at 1.0)

### README "Upgrading from 0.1.x" section

A transitional `0.1.x → 0.2.0` migration table at the bottom of `README.md` (marked with an
`<!-- TEMPORARY … -->` comment). **Delete at 1.0** — by then the pre-0.2.0 surface (the
`Axn::MCP::Tool` base, `.define`, `mcp_text_content`, `error_headline`, bang-methods) is gone
entirely and there's nothing to migrate from.

### `Axn::MCP::Tool` (subclass base)

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

### `Axn::MCP::Tool.define` (inline factory)

Removed alongside the base (the raising tombstone above covers it). It was pure sugar over
composing two public primitives; use them directly:

```ruby
Axn::MCP.wrap(
  Axn::Factory.build(expects: { query: { type: String } },
                     exposes: { results: { type: Array } }) { expose results: Item.search(query) },
  name: "search", description: "Search for items",
)
```

### `Axn::MCP.wrap(mcp_text_content:)` kwarg

Renamed to `present_as:` (unifying the "structured data vs. the Axn message" render toggle with
`axn-ruby_llm`'s `present_as`, and dropping the redundant `mcp_` prefix that doubled up inside the
`:mcp` config namespace). The old kwarg is kept as a **raising alias**: passing `mcp_text_content:`
raises `ArgumentError` pointing at `present_as:`.

**Delete at 1.0:** remove the `mcp_text_content:` parameter and `reject_renamed_mcp_text_content!`
from `Axn::MCP.wrap` (`lib/axn/mcp/wrap.rb`).

## Removed (no stub)

- **`present_as` config setting was `mcp_text_content`** — the gem-wide
  `Axn::MCP.config.present_as` and the per-class `configure(:mcp) { |c| c.present_as = ... }`
  setting were renamed from `mcp_text_content`. Nothing is released, so this is a hard rename: the
  old `config.mcp_text_content` raises `NoMethodError` and `configure(:mcp) { |c| c.mcp_text_content
  = ... }` raises `ArgumentError` (unknown setting) — both surfaced by axn core's config DSL, so
  they aren't given a pointed migration message the way the `wrap` kwarg is. Use `present_as`
  (`:structured` / `:message`).

- **`Axn::MCP.config.error_headline`** — the gem no longer imposes a `"Tool call
  failed"` headline on failures. MCP error responses now carry the Axn's own `result.error`.
  A tool that wants a generic failure message declares its own axn base `error "..."` (standard
  axn practice), which is per-tool rather than gem-wide.
- **Annotation bang-methods** `read_only!` / `destructive!` / `idempotent!` / `open_world!` /
  `closed_world!`, and the **`open_world` / `closed_world`** class helpers — these lived only on
  the retired `Axn::MCP::Tool` base. Declare `semantic_hints :read_only, :closed_world, ...` on
  the plain Axn instead (axn core registers `:open_world`/`:closed_world` as MCP-specific hints);
  `Axn::MCP.wrap` maps them to MCP annotations, and an explicit `annotations:` kwarg on `wrap`
  still wins.
