# Changelog

## 0.2.0

- Fixed `Axn::MCP.wrap` ignoring a wrapped Axn's own per-action `mcp_text_content` override (set via
  `MyAxn.configure(:mcp) { |c| c.mcp_text_content = :message }`) when `wrap` itself wasn't given an
  explicit `mcp_text_content:` kwarg — it fell straight back to the gem-wide config. Now resolves
  through `Axn::MCP.resolve_override_for(axn_class, :mcp_text_content)`, axn core's shadow-proof
  override resolver, rather than `axn_class.mcp_text_content` — the wrapped Axn may never have
  included `Axn::MCP.overrides` at all (it's a plain Axn, not an `Axn::MCP::Tool` subclass), so it
  may have no such accessor to call. Precedence is now: `wrap`'s own `mcp_text_content:` kwarg, then
  the wrapped Axn's per-action override, then the gem-wide config.
- `Axn::MCP.wrap` accepts `title:`/`icons:`/`meta:` kwargs, mirroring `::MCP::Tool`'s own class
  methods of the same name — a wrapped Axn has no class body of its own in which to declare them.
  A class subclassing `Axn::MCP::Tool` already had these for free via plain inheritance (no
  shadowing — axn core touches neither name); documented that path too, plus the new `wrap` kwargs
  — per PRO-2879 item 1.
- Documented `MCP::ServerContext`'s richer capabilities (`#report_progress`, `#cancelled?`, etc.) —
  reachable today with no gem changes, but previously discoverable only by reading the `mcp` gem's
  own source — per PRO-2879 item 2.
- Documented in the README's intro that this gem is scoped to MCP Tools only — Resources, Resource
  Templates, and Prompts are `MCP::Server` concepts this gem doesn't adapt an Axn into — per
  PRO-2879 item 3.
- Documented that schema reflection is best-effort and deliberately biased stricter-than-runtime (a
  client following the schema won't be rejected by schema validation, but the schema may
  occasionally be more restrictive than what the tool would actually accept) — per axn PRO-2842
  review feedback. `Axn::MCP.wrap` now wires directly to the wrapped Axn's own public
  `input_schema`/`output_schema` reflection methods rather than reaching past them for the
  lower-level schema builder.
- Softened the README's schema-reflection claim from "will never trigger a failed call" to name its
  one documented exception: a field with an invalid default (e.g. `default: 123` on a `String`
  field) reflects as optional (a default is present) without axn validating the default itself, so
  omitting the field applies the bad default and fails at runtime despite the schema saying it's
  fine to omit. This is the one spot where the input schema is *looser* than runtime, not stricter —
  deliberately left open rather than closed with declaration-time default-validation, since that
  would only catch literal defaults, not custom validators/callable defaults/model lookups. Matters
  here because `MCP::Server` pre-flight-validates arguments against `inputSchema`
  (`validate_tool_call_arguments`, on by default), so a schema-valid call can still fail at runtime
  in this narrow case. Tracked as a known gap, not a bug — PRO-2879 item 4.
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
  :ambient_context, type: Object`). Its exact class now depends on how the tool was invoked and
  which `mcp` gem version is in use: a direct/test-style call passing a plain `Hash` gets it
  resolved to an `ActiveSupport::HashWithIndifferentAccess` (a consequence of axn core's
  ambient-context machinery — `is_a?(Hash)`/`#[]`/`#dig` still work as before, including with
  symbol keys; `instance_of?(Hash)` and `#==` against a literal symbol-keyed `Hash` do not); a real
  `MCP::Server` round-trip on recent `mcp` gem versions instead passes an `MCP::ServerContext`
  object, which isn't Hash-like at all but transparently delegates `#dig`/`#[]`/etc. to whatever
  context object the server was configured with. `type: Object` (not `Hash`) reflects that the
  field's runtime shape isn't fixed. Read with `&.dig(...)`/`&.[]` rather than asserting a class —
  that works uniformly across both cases and is unchanged from before this release. The
  `server_context` reader inside a tool's `#call` is otherwise unchanged: still the raw injected
  value, still `nil` when the tool is called directly without `server_context:`, and still excluded
  from `inputSchema`. An explicit `server_context:` now also fully replaces any process-wide
  `Current`-attributes-derived ambient context for that call, so no server-side state can leak into
  an MCP invocation.
- Added `Axn::MCP.wrap(any_axn, description:, **opts)`, exposing a plain Axn (one that does *not*
  subclass `Axn::MCP::Tool`) as an `::MCP::Tool` subclass — "author once," per axn PRO-2842/PRO-2844.
  A wrapped Axn that needs server-injected data must declare its own `expects :server_context, on:
  :ambient_context, type: Object` (the same convention `Axn::MCP::Tool` itself uses) and read it via
  `server_context&.dig(...)`. `name:` defaults to a snake-cased version of the wrapped Axn's own
  class name when omitted (needed for the common inline `tools: [Axn::MCP.wrap(...)]` registration,
  since an unassigned anonymous class has no name of its own); raises `ArgumentError` instead of
  silently registering an unnamed, unusable tool if the wrapped Axn is also anonymous.
- Added `open_world`/`closed_world` as `semantic_hints`, registered via
  `Axn.extension_config.register_semantic_hint` (axn core's new extension registry) — no core change
  needed to add MCP-spec-only vocabulary. A class's declared `semantic_hints` now drive its MCP
  annotations by default (`:read_only`/`:idempotent`/`:destructive`/`:open_world`/`:closed_world` →
  the matching `*_hint`), unless the class calls `annotations(...)` explicitly, which always wins.
- **Deprecated** `read_only!`/`destructive!`/`idempotent!`/`open_world!`/`closed_world!`. They still
  work — now as thin aliases over `semantic_hints` (previously an independent mechanism that never
  updated `.semantic_hints` at all) — but emit a deprecation warning via a dedicated
  `Axn::MCP.deprecator` (an `ActiveSupport::Deprecation` instance; a consuming Rails app can register
  it with `Rails.application.deprecators` to govern its behavior like its own deprecations) and will
  be removed in a future release. `read_only!`/`destructive!` and `open_world!`/`closed_world!` are
  still mutually exclusive with each other, matching their old full-replace behavior;
  `idempotent!` composes with either, same as before. Prefer `semantic_hints`/`open_world`/
  `closed_world` directly going forward.
- Removed the `::MCP::Tool.singleton_class.instance_method(:x).bind(self).call(...)` workarounds
  for `Axn::MCP::Tool#input_schema`/`#output_schema`, and the `#description` override entirely —
  axn's new `Axn::Core::MethodShadowing` (axn PRO-2875, filed from this gem's own PRO-2844 work) now
  defers to a pre-existing same-named method on a non-axn-core ancestor, so `include Axn` no longer
  shadows `::MCP::Tool`'s own `description`/`input_schema`/`output_schema` in the first place; plain
  `super`/inheritance works again. The `#annotations` bind-trick remains — unrelated to this fix, a
  `NOT_SET` sentinel mismatch between this gem's own sentinel and `::MCP::Tool`'s internal one, not
  an axn-core shadowing issue.
- Removed `Axn::MCP::FieldDeclarations` entirely (no external references found) — `Tool.define` now
  calls axn core's new public `Axn::FieldDeclarations.hydrate` (axn PRO-2878) directly instead of
  duplicating the identical `expects:`/`exposes:` declaration-format normalization. `Axn::Factory`'s
  own "must provide a callable/block" contract is intentionally unchanged (building a callable into
  an Axn is its whole purpose); `Tool.define` still isn't backed by `Axn::Factory.build` itself, and
  now isn't expected to be — the shared piece both needed was this normalizer, not the factory.
- `Axn::MCP` now declares `config_namespace :mcp` (axn core's namespaced per-class config, axn
  PRO-2880), so a base Axn can be configured for this gem and for another adapter (e.g. an
  `axn-ruby_llm` gem declaring its own `config_namespace`) independently on the same class, via
  `configure(:mcp) { |c| c.mcp_text_content = :message }` / `configure(:other_adapter) { |c| ... }`.
  Purely additive — the flat `mcp_text_content(...)` accessor and gem-wide
  `Axn::MCP.config.mcp_text_content` are unchanged; this only adds the namespaced
  `configure`/`axn_configure` DSL as an alternate way to set the same per-tool override.
- **[BREAKING]** `resolved_mcp_text_content` is removed — axn core removed `resolved_<name>`
  entirely (axn PRO-2888), since it was byte-for-byte identical to the no-arg `mcp_text_content`
  reader. Read `SomeTool.mcp_text_content` instead of `SomeTool.resolved_mcp_text_content`; the
  per-tool setter form (`mcp_text_content :message`) and gem-wide
  `Axn::MCP.config.mcp_text_content` are unaffected. This gem never used `raw_mcp_text_content`
  (also renamed upstream, to `mcp_text_content_override`), so that rename needs no local change.
- Requires an `axn` version that ships `Axn::Core::SchemaReflection`, `Axn::Core::SemanticHints`,
  `Axn::Core::AmbientContext`, `Axn::Core::MethodShadowing`, `Axn::FieldDeclarations`,
  `Axn::ExtensionConfig#register_semantic_hint`, `Axn::Reflection::{Schema,Values}`, and
  `Axn::Configurable`'s namespaced `config_namespace` plus the `resolved_<name>`
  removal/`raw_<name>` rename (axn PRO-2842 / PRO-2875 / PRO-2878 / PRO-2880 / PRO-2888). As of
  this writing, axn has no tagged release with these primitives yet; this gem's Gemfile currently
  tracks `axn` git `main` (`github: "teamshares/axn", branch: "main"`) pending an axn release.

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
