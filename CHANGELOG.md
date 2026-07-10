# Changelog

## 0.2.0

- Adopted `axn` core's JSON Schema reflection (`Axn::Reflection::Schema`) and exposed-value
  serialization (`Axn::Reflection::Values`), added in axn PRO-2842. `Axn::MCP::SchemaBuilder` and
  the old `Axn::MCP::Serializer.serialize_exposed`/`.serialize_value` methods are removed — schema
  and serialization logic now lives in axn core, and is a strict superset of the old behavior:
  nullable fields now reflect as a `type` array (e.g. `["string", "null"]`) instead of a bare type;
  boolean fields gain an explicit `enum: [true]`/`[false]` alongside `type: "boolean"`; a
  `model: true` field's generated `_id` property no longer asserts `type: "integer"` (a model's
  primary key type isn't knowable from the declaration) but does forbid `null` when required; every
  `exposes`-declared field is now listed in output `required` (an optional exposed field's
  optionality instead shows up as a nullable `type`); a `type: Numeric` field's JSON type is
  omitted on output (it admits `Complex`, whose wire form isn't statically knowable); and a
  `shape:` block on an `Array` field with no `of:` is no longer reflected in the *output* schema
  (combine `shape:` with `of:` for typed output items — the `expects` input schema is unaffected).
- `server_context` is no longer a declared top-level field on `Axn::MCP::Tool` — it's routed
  through axn core's new `ambient_context` mechanism (`expects :server_context, on:
  :ambient_context`). It also now arrives as an `ActiveSupport::HashWithIndifferentAccess`, not a
  plain `Hash` — a direct consequence of being resolved through axn core's ambient-context
  machinery. `is_a?(Hash)`, `#[]`, and `#dig` all still work as before (including with symbol
  keys); `instance_of?(Hash)` no longer holds, and `#==` against a literal `Hash` with symbol keys
  no longer holds either (`{ "user_id" => 42 }` matches; `{ user_id: 42 }` does not). The
  `server_context` reader inside a tool's `#call` is otherwise unchanged: still the raw injected
  value, still `nil` when the tool is called directly without `server_context:`, and still excluded
  from `inputSchema`. An explicit `server_context:` now also fully replaces any process-wide
  `Current`-attributes-derived ambient context for that call, so no server-side state can leak into
  an MCP invocation.
- Added `Axn::MCP.wrap(any_axn, description:, **opts)`, exposing a plain Axn (one that does *not*
  subclass `Axn::MCP::Tool`) as an `::MCP::Tool` subclass — "author once," per axn PRO-2842/PRO-2844.
  A wrapped Axn that needs server-injected data must declare its own `expects :server_context, on:
  :ambient_context, type: Hash` (the same convention `Axn::MCP::Tool` itself uses) and read it via
  `server_context&.dig(...)`.
- Added `open_world`/`closed_world` as `semantic_hints`, registered via
  `Axn.extension_config.register_semantic_hint` (axn core's new extension registry) — no core change
  needed to add MCP-spec-only vocabulary. A class's declared `semantic_hints` now drive its MCP
  annotations by default (`:read_only`/`:idempotent`/`:destructive`/`:open_world`/`:closed_world` →
  the matching `*_hint`), unless the class calls `annotations(...)` explicitly, which always wins.
  `read_only!`/`destructive!`/`idempotent!`/`open_world!`/`closed_world!` remain as unchanged,
  independent convenience methods.
- Requires an `axn` version that ships `Axn::Core::SchemaReflection`, `Axn::Core::SemanticHints`,
  `Axn::Core::AmbientContext`, `Axn::ExtensionConfig#register_semantic_hint`, and
  `Axn::Reflection::{Schema,Values}` (axn PRO-2842). As of this writing, axn has no tagged release
  with these primitives yet; this gem's Gemfile currently tracks `axn` git `main`
  (`github: "teamshares/axn", branch: "main"`) pending an axn release.

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
