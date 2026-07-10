# Changelog

## 0.1.1

- Migrated internal configuration off hand-rolled code onto the upstream `Axn::Configurable` DSL (added in axn PRO-2769). The public surface is unchanged: `Axn::MCP.config.mcp_text_content`, per-tool `mcp_text_content(...)` overrides, and `resolved_mcp_text_content` all behave as before.
- `Axn::MCP::Tool` now declares a base error headline, default `"Tool call failed"` (leveraging axn's error-prefix feature). Failures with no explicit reason — validation errors, unexpected exceptions, bare `fail!` — now surface as the headline alone instead of axn's generic `"Something went wrong"`, and explicit reasons are contextualized as `"<headline>: <reason>"`. The headline is a proper `Axn::MCP.config.error_headline` setting (String, non-blank), resolved fresh on every failure — set it gem-wide with no reload or require-order caveat. Subclasses can still override with their own base `error "..."`, which wins over the configured headline, or opt a single message out with `fail!("...", standalone: true)`. The headline presentation is uniform across `call` and `call!`: a failing `call!` raises an `Axn::Failure` whose `#message` matches `result.error` (e.g. `"Tool call failed: <reason>"`).
- Requires an `axn` version that ships `Axn::Configurable`, base-`error` prefixing, and the `standalone:` message flag (axn PRO-2746 / PRO-2820 / PRO-2832).
- Schema generation (`input_schema`/`output_schema`) now delegates to axn core's `Axn::Reflection::Schema` instead of this gem's own (now-deleted) `Axn::MCP::SchemaBuilder`. Consumer-visible schema-output changes: a nullable field's `type` is now an array (e.g. `["string", "null"]`) instead of a bare type; `TrueClass`/`FalseClass` fields gain an `enum: [true]`/`[false]` alongside `type: "boolean"`; a `model: true` field's generated `_id` property no longer asserts `type: "integer"` (a model's primary key type isn't knowable from the declaration) but does forbid `null` (`not: { type: "null" }`) when required; every `exposes`-declared field is now listed in output `required` (JSON Schema `required` means property presence, and every exposed key is always present in the serialized result — an optional exposed field's optionality shows up as a nullable `type` instead); a `type: Numeric` field's JSON type is omitted on output (it admits `Complex`, whose wire form isn't statically knowable); and a `shape:` block on an `Array` field with no `of:` is no longer reflected in the OUTPUT schema (output can't prove the elements serialize to a member-keyed object without a declared `of:` — combine `shape:` with `of:` for typed output items, or rely on the `expects` input schema, which is unaffected). `server_context` continues to be excluded from `input_schema`, now filtered by `Axn::MCP::Tool` itself rather than the deleted builder.

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
