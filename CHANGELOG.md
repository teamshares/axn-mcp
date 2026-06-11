# Changelog

## Unreleased

- Bump `axn` dependency to `>= 0.1.0-alpha.4.3` (adds `of:` and `shape:` block support)
- `SchemaBuilder` now emits `items:` in JSON Schema for `Array`-typed fields that use `of:`:
  - Scalar types (`of: String`, `of: :boolean`, `of: :uuid`, etc.) → typed `items`
  - Union types (`of: [String, Numeric]`) → `items: { anyOf: [...] }`
  - `Data.define` subclasses (`of: MyRecord`) → `items: { type: "object", properties: { <member>: {} } }`
- `SchemaBuilder` now consumes `shape:` block contracts (PRO-2651):
  - `Array` field with `shape:` block → typed `items.properties` with `required` derivation
  - `Hash` field with `shape:` block → typed `properties` with `required` derivation
  - Nested `shape:` blocks recurse correctly
  - When both `of: <Data.define>` and a `shape:` block are present, Data members provide the bare baseline and block-declared members are overlaid with full type info (enrich)

## 0.1.0

- Initial release
- `Axn::MCP::Tool` base class for building MCP tools with Axn
- Auto-generated JSON schemas from `expects`/`exposes` declarations
- Automatic `model:` field handling (exposes `_id` field to LLM)
- Auto-serialization of exposed values to JSON-safe structures
- Annotation shortcuts: `read_only!`, `destructive!`, `idempotent!`, `open_world!`, `closed_world!`
- Factory-style `Tool.define` for quick one-off tools
- Dual-use: returns `Axn::Result` for direct calls, `MCP::Tool::Response` when called via MCP server
