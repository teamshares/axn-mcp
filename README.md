# Axn::MCP

Build [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) tools using [Axn](https://github.com/teamshares/axn)'s declarative `expects`/`exposes` contract. This gem wraps the official [MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk) and auto-generates JSON schemas from your Axn field declarations.

**Author once, expose anywhere.** You write a plain Axn — a normal action, usable by any caller — and this gem exposes it as an `::MCP::Tool` with `Axn::MCP.wrap` (one tool) or `Axn::MCP.tools` (every registered tool at once). The Axn stays a plain Axn: called directly it returns an `Axn::Result`, with no MCP awareness. The same action can be exposed to other adapters (e.g. an `axn-ruby_llm`) the same way, from the same class.

> **Migrating from the `Axn::MCP::Tool` subclass base?** It was retired in favor of `Axn::MCP.wrap` (see [DEPRECATIONS.md](DEPRECATIONS.md)). Subclassing it now raises with a migration message. The change is a one-liner per tool — see [Exposing tools](#exposing-tools).

This gem is scoped to MCP **Tools** only. `MCP::Server` also supports `resources`, `resource_templates`, and `prompts` as first-class concepts — `Axn::MCP.wrap` doesn't adapt an Axn into any of those, and there's no `Axn::MCP.wrap_as_resource` or equivalent. If you need those, register them with `MCP::Server` directly per the [MCP Ruby SDK documentation](https://github.com/modelcontextprotocol/ruby-sdk).

## Installation

Add to your Gemfile:

```ruby
gem "axn-mcp"
```

Then run:

```bash
bundle install
```

## Quick Start

Write a plain Axn, then expose it with `Axn::MCP.wrap`:

```ruby
class GreetUser
  include Axn

  description "Greet a user by name"

  expects :name, type: String, description: "The user's name"
  exposes :greeting, type: String, description: "The greeting message"

  def call
    expose greeting: "Hello, #{name}!"
  end
end

GreetUserTool = Axn::MCP.wrap(GreetUser) # => an ::MCP::Tool subclass, ready to register
```

`Axn::MCP.wrap` returns a genuine `::MCP::Tool` subclass. The gem automatically:

- Generates `inputSchema` from your `expects` declarations
- Generates `outputSchema` from your `exposes` declarations
- Converts `Axn::Result` to `MCP::Tool::Response`
- Serializes exposed data to JSON-safe `structured_content`

`GreetUser` itself is untouched — `GreetUser.call(name: "Alice")` still returns a plain `Axn::Result`.

`inputSchema`/`outputSchema` generation and exposed-value serialization are both sourced from
`axn` core's own reflection APIs (`Axn::Reflection::Schema` and `Axn::Reflection::Values`) — this
gem no longer carries its own schema-building or serialization logic.

**Reflection is best-effort and deliberately biased stricter-than-runtime.** Schemas are built
*statically* from your `expects`/`exposes` declarations — reflection is side-effect-free and never
runs your validators. Where a value's wire form isn't *provable* from the declared type, the schema
reflects the conservative answer (untyped, required, or non-null) rather than guess. The net
contract: **a client that follows the schema will not be rejected by schema validation; the schema
may occasionally be more restrictive than what the tool would actually accept at runtime.**
Concretely, you may see: `type` omitted entirely (an untyped `{}`) when the wire form isn't knowable
(e.g. a `Numeric`/`Complex` field, or a reader-only/custom-serialized object); `not: { type: "null"
}` on a required `model:`-generated `_id` (a primary key has no fixed JSON type); `enum:
[true]`/`[false]` for a `TrueClass`/`FalseClass` field; and `anyOf` for union types.

This isn't an absolute "schema-valid implies success" guarantee, though: a schema-following call can
still fail axn's own runtime validation in the narrow case where a field's contract is
self-contradictory — e.g. `expects :name, type: String, default: 123` reflects `name` as *optional*
(a default is present), but omitting it applies the invalid default and then fails runtime
validation. Reflection derives requiredness from the declared *signals* (a present default,
`optional:`/`allow_nil:`/`allow_blank:`) without evaluating whether the default itself is valid —
catching that would only cover literal defaults, not custom validators, callable defaults, or model
lookups, so the caveat exists either way. This is the one documented spot where the input schema is
*looser* than runtime rather than stricter (a known, deliberate gap, not a bug).

## Exposing tools

An Axn is just an action; the gem turns it into an `::MCP::Tool` at the edge. There are three ways
in, all producing the same kind of `::MCP::Tool` subclass.

### One tool: `Axn::MCP.wrap`

```ruby
GreetUserTool = Axn::MCP.wrap(GreetUser)
```

`wrap(axn_class, description: nil, name: nil, title: nil, icons: nil, meta: nil, annotations: nil, present_as: nil)`:

- **`description:`** defaults to the Axn's own `.description`. Pass it to override.
- **`name:`** defaults to `axn_class.tool_name` — axn core's canonical, provider-safe name, which
  honors a `tool name: "..."` override on the Axn and any configured `tool_name_stripped_prefixes`
  (e.g. `GreetUser` → `"greet_user"`). Pass `name:` to override. This matters if you register the
  tool inline (`tools: [Axn::MCP.wrap(GreetUser)]`) rather than assigning it to a constant. If the
  wrapped Axn is *truly* anonymous (no class name, no `axn_name`), `wrap` raises `ArgumentError`
  rather than ship an unusable, unnamed tool — pass `name:` in that case.
- **`annotations:`** / **`present_as:`** / **`title:`** / **`icons:`** / **`meta:`** — all
  optional; see the sections below. Omitted values fall through to the Axn's own declarations
  (`semantic_hints`, `configure(:mcp)`) or `::MCP::Tool`'s defaults.

The original class is never modified — the transport concerns (schema, `server_context` routing,
response mapping) live entirely on the generated subclass:

```ruby
GreetUserTool.input_schema_value.to_h[:properties].keys        # => [:name]
GreetUserTool.call(name: "Bob", server_context: { user_id: 42 }) # => MCP::Tool::Response
GreetUser.call(name: "Alice")                                    # => Axn::Result (untouched)
```

Unlike the retired base, the generated subclass has no dual mode: its `.call` **always** returns
`MCP::Tool::Response`, and it has no `.call!` (a bang that just delegated to `.call` would promise
raise-on-failure semantics it can't deliver — call the original Axn's `.call!` if you want those).

### Every registered tool: `Axn::MCP.tools`

Mark an Axn as an MCP tool with `tool :mcp` (axn core's tool-registry DSL), and `Axn::MCP.tools`
returns them all, already wrapped — no hand-maintained array:

```ruby
class ListCompanies
  include Axn
  tool :mcp
  description "List companies"
  # ...
end

MCP::Server.new(name: "my-server", version: "1.0.0", tools: Axn::MCP.tools)
```

`Axn::MCP.tools` is `Axn.tools_for(:mcp).map { |axn| Axn::MCP.wrap(axn) }` — zero-arg by design.
Per-tool customization comes from each class's own declarations (`tool name:`, `description`,
`semantic_hints`, `configure(:mcp)`), all honored inside `wrap`. It's symmetric with the same
pattern in sibling adapter gems (e.g. `Axn::RubyLLM.tools`).

A class becomes a `:mcp` member via any of:

- **`tool :mcp`** (or bare `tool`, meaning every registered adapter) — the explicit opt-in
- an implicit **`configure(:mcp) { ... }`** block on the class (declaring MCP config implies membership)
- **residency under a configured `Axn.config.tool_paths` directory** — set `Axn.config.tool_paths = ["app/actions/tools"]` (relative to `Rails.root/app`, or absolute); every Axn under it is auto-registered without an explicit `tool` declaration. Opt one out with `tool false`.

**The class must be loaded for `Axn::MCP.tools` to see it** — the registry only enumerates
currently-defined classes. `tool_paths` directories are eager-loaded on demand (and by Rails
eager-loading); a `tool :mcp` class that lives *outside* a `tool_path` and isn't otherwise required
won't appear until its file is loaded. Enumerate from `config.after_initialize` / a `to_prepare`
block (not a `config/initializers` file) for reliable results under Rails.

For a curated subset instead of all of them, filter the registry yourself:
`Axn.tools_for(:mcp).select { ... }.map { |a| Axn::MCP.wrap(a) }`.

### One-off inline tools

There's no `Axn::MCP.define`; the inline primitive lives in axn core. For a throwaway tool, build a
plain Axn with `Axn::Factory.build` (block-as-`#call`, no class needed) and wrap it:

```ruby
# The block is the Axn's #call body — pass it to Axn::Factory.build.
search = Axn::Factory.build(
  expects: { query: { type: String, description: "Search query" } },
  exposes: { results: { type: Array } },
) do
  expose results: Item.search(query)
end

SearchTool = Axn::MCP.wrap(search, name: "search", description: "Search for items", annotations: { read_only_hint: true })
```

`Axn::Factory.build` carries the action's behavior — the `#call` block plus
`expects`/`exposes`/`success`/`error`/hooks/… — while the MCP-facing bits
(`name:`/`description:`/`annotations:`/`present_as:`) go to `wrap`. For a multi-adapter one-off,
build the Axn once and hand it to each adapter's `wrap`.

### Mixing with native `::MCP::Tool` tools

Because `wrap` returns a real `::MCP::Tool` subclass, wrapped Axns and hand-written MCP tools
compose in one array — splat `Axn::MCP.tools` alongside anything else:

```ruby
MCP::Server.new(
  name: "my-server", version: "1.0.0",
  server_context: { user_id: current_user.id },
  tools: [
    *Axn::MCP.tools,                                   # every registered :mcp Axn, wrapped
    NativeSearchTool,                                  # a plain MCP::Tool subclass
    MCP::Tool.define(name: "ping", description: "…") { |_args, _sc| MCP::Tool::Response.new([...]) },
  ],
)
```

`server_context` flows identically to both: native tools read it in `call(args, server_context:)`;
wrapped Axns get it routed into `ambient_context` (see [Server Context](#server-context)).

## Field declarations & schema

The schema mappings below are axn core reflection surfaced through `wrap` — declare fields on a
plain Axn (`include Axn`), and the shapes appear on `Axn::MCP.wrap(TheAxn).input_schema_value` /
`.output_schema`.

### Field Descriptions

Use `description:` directly as a kwarg on `expects` and `exposes`:

```ruby
expects :start_date, type: Date, optional: true, description: "Inclusive lower bound (YYYY-MM-DD)"
exposes :results,    type: Array,                description: "Matching records"
```

> **Note:** Do *not* wrap it in `metadata: { description: ... }`. The `metadata:` key is not recognized by `expects`/`exposes` and raises `ArgumentError` at class load time.

### Type Mappings

Axn types map to JSON Schema types:


| Ruby Type          | JSON Schema                    |
| ------------------ | ------------------------------ |
| `String`           | `string`                       |
| `Integer`          | `integer`                      |
| `Float`, `Numeric` | `number`                       |
| `Hash`             | `object`                       |
| `Array`            | `array`                        |
| `:boolean`         | `boolean`                      |
| `:uuid`            | `string` (format: `uuid`)      |
| `Date`             | `string` (format: `date`)      |
| `DateTime`, `Time` | `string` (format: `date-time`) |

### Coercing loosely-typed inbound values with `coerce:`

An LLM (or a client that stringifies its JSON) doesn't always send a value in the exact Ruby type your `expects` field declares — a `Date`/`Integer`/`Float`/`Symbol`/`Time`/`DateTime` field can arrive as a `String`. Add the `coerce: <Type>` shorthand (or `type: { klass: <Type>, coerce: true }` when you also need other type options alongside it — `coerce:` can't be combined with a sibling top-level `type:`) to have `axn` core convert a well-formed string to the declared type *before* validation runs:

```ruby
expects :starts_on, coerce: Date                          # "2026-01-15" -> a Date
expects :count,     type: { klass: Integer, coerce: true } # "42" -> 42
```

Coercion applies to inbound `expects` fields — top-level **and** subfields declared with `on:` (including ambient subfields, e.g. `server_context` values). It is **not** available on `exposes` (outbound values are serialized, not coerced) or on `shape:` block members — both *raise at class-definition* if given `coerce:`. Only a non-blank `String` is converted. An unparseable string doesn't silently fall through to a generic type-mismatch: coercion raises `Axn::InboundValidationError` carrying a specific `"<field> could not be coerced to a <Type>"` message — but, like any validation failure, that detail rides on the exception (logs / `on_exception`), while the tool's response to the client carries axn's user-facing `result.error` (`"Something went wrong"` by default, or the tool's own base `error "…"` — see [Error Handling](#error-handling)). `inputSchema`/`outputSchema` output is identical with or without `coerce:` — only accepted inbound values change, not the field's advertised JSON type.


### Typed member contracts with `shape:`

Add a `shape:` block to a `Hash` or `Data.define` field to declare types and validations for its members. `required` is derived automatically; unannotated members on a `Data.define` type appear as bare `{}`. The block syntax is the same on both `expects` and `exposes`. (For `Array` fields, combine `shape:` with `of:` — see the next section.)

**Hash field:**

```ruby
exposes :config, type: Hash do
  field :region,  type: String
  field :timeout, type: Integer, optional: true
end
```

```json
{
  "type": "object",
  "required": ["region"],
  "properties": {
    "region":  { "type": "string" },
    "timeout": { "type": ["integer", "null"] }
  }
}
```

Requiredness and nullability are two orthogonal JSON Schema signals, not a redundancy: a member's *requiredness* is tracked solely by the `required` array (`region` is listed, so it's required); an *optional* member is omitted from `required` **and** additionally reflects a nullable `type` array (`["integer", "null"]`) — because an omittable field may resolve to null. So a required member shows up in `required` with a bare type, while an optional one is absent from `required` with a nullable type; that's why the `of:`/`shape:` examples below show `status` (required) in `required` but `active` (optional) as `["boolean", "null"]`.

**`Data.define` struct:**

```ruby
IntegrationRecord = Data.define(:source, :provider_name, :active, :status)

exposes :integration, type: IntegrationRecord do
  field :status, type: String, inclusion: { in: %w[connected error needs_reconnect] }
  field :active, type: :boolean, optional: true
end
```

```json
{
  "type": "object",
  "required": ["status"],
  "properties": {
    "status":        { "type": "string", "enum": ["connected", "error", "needs_reconnect"] },
    "active":        { "type": ["boolean", "null"] },
    "source":        {},
    "provider_name": {}
  }
}
```

Blocks recurse naturally for nested objects:

```ruby
exposes :config, type: Hash do
  field :region,    type: String
  field :retention, type: Hash do
    field :days, type: Integer
  end
end
```

### Typed array elements with `of:`

When an `Array` field carries an `of:` declaration, the generated JSON Schema includes a machine-readable `items:` entry rather than a bare `array` type.

**Scalar element type:**

```ruby
exposes :tags, type: Array, of: String
```

```json
{ "type": "array", "items": { "type": "string" } }
```

Other supported forms: `of: Integer`, `of: :boolean`, `of: :uuid`, and union types:

```ruby
exposes :values, type: Array, of: [String, Numeric]
```

```json
{ "type": "array", "items": { "anyOf": [{ "type": "string" }, {}] } }
```

(The `Numeric` member is left untyped: it admits `Complex`, whose serialized wire form isn't knowable from the declaration alone.)

**`Data.define` struct — bare member names as baseline:**

```ruby
exposes :integrations, type: Array, of: IntegrationRecord
```

```json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": { "source": {}, "provider_name": {}, "active": {}, "status": {} }
  }
}
```

**Combine `of:` with a `shape:` block to annotate element members:**

```ruby
exposes :integrations, type: Array, of: IntegrationRecord do
  field :status, type: String, inclusion: { in: %w[connected error needs_reconnect] }
  field :active, type: :boolean, optional: true
end
```

```json
{
  "type": "array",
  "items": {
    "type": "object",
    "required": ["status"],
    "properties": {
      "status":        { "type": "string", "enum": ["connected", "error", "needs_reconnect"] },
      "active":        { "type": ["boolean", "null"] },
      "source":        {},
      "provider_name": {}
    }
  }
}
```

Annotated members are fully typed; unannotated `Data.define` members (`source`, `provider_name`) remain as bare `{}`.

### ActiveRecord Model Fields

When using `model: true`, the schema automatically generates an `_id` field with an appropriate description:

```ruby
class UpdateUser
  include Axn

  description "Update a user's profile"

  expects :user, model: true
  expects :name, type: String, optional: true

  def call
    user.update!(name:) if name
  end
end
```

Generates schema:

```json
{
  "properties": {
    "user_id": {
      "description": "ID of the User record",
      "not": { "type": "null" }
    }
  }
}
```

The generated id field's JSON type is intentionally left unconstrained — a model's primary key isn't
knowable from the declaration (it could be an integer, UUID, string, etc.), and inferring it would
require a database lookup. A required model field's id still forbids `null` (a null token can never
resolve to a record).

### Enums via Inclusion

```ruby
expects :status, inclusion: { in: %w[active inactive pending] }
```

Generates:

```json
{
  "status": {
    "type": "string",
    "enum": ["active", "inactive", "pending"]
  }
}
```

## Annotations

Declare `axn` core's generic `semantic_hints` DSL (`semantic_hints :read_only, :idempotent, ...`) on your Axn, and `Axn::MCP.wrap` maps them to MCP annotations automatically. This gem registers `:open_world`/`:closed_world` as additional semantic hints (via `Axn.extension_config.register_semantic_hint` — no core change needed for MCP-only vocabulary):

| Declared `semantic_hints` | Default annotation      |
| -------------------------- | ------------------------ |
| `:read_only`                | `read_only_hint: true`, `destructive_hint: false` |
| `:idempotent`               | `idempotent_hint: true`  |
| `:destructive`              | `destructive_hint: true` |
| `:open_world`               | `open_world_hint: true`  |
| `:closed_world`             | `open_world_hint: false` |

```ruby
class FetchData
  include Axn
  description "Fetch data without side effects"
  semantic_hints :read_only, :closed_world
  # Axn::MCP.wrap(FetchData) => annotations include read_only_hint: true, destructive_hint: false, open_world_hint: false
  # ...
end
```

For anything `semantic_hints` doesn't cover (a custom annotation `title`, or an annotation with no corresponding hint), set `annotations` directly — either as a `wrap` kwarg or via `configure(:mcp)` (the latter survives `Axn::MCP.tools`). Precedence: `wrap` kwarg → `configure(:mcp)` → the `semantic_hints`-derived default.

```ruby
# At wrap time:
Axn::MCP.wrap(MyAxn, annotations: { read_only_hint: true, idempotent_hint: true, title: "My Custom Tool" })

# Or declaratively (picked up by Axn::MCP.tools):
class MyAxn
  include Axn
  tool :mcp
  configure(:mcp) { |c| c.annotations = { read_only_hint: true, idempotent_hint: true, title: "My Custom Tool" } }
  # …
end
```

## Title, Icons, and Metadata

`::MCP::Tool` supports `title`/`icons`/`meta` alongside `description`/`annotations`. Set them either as `wrap` kwargs, or declaratively on the Axn via `configure(:mcp)` — the latter survives the zero-arg `Axn::MCP.tools` path (which calls `wrap` with no kwargs), so it's how you attach this metadata to a registry-enumerated tool. An explicit `wrap` kwarg wins over the `configure(:mcp)` value; both are omitted (left at `::MCP::Tool`'s own defaults) unless set.

```ruby
# At wrap time:
Axn::MCP.wrap(
  SearchAxn,
  description: "Search for items",
  title: "Item Search",
  icons: [{ src: "https://example.com/icon.png", mimeType: "image/png" }],
  meta: { version: "1.0" },
)

# Or declaratively (picked up by Axn::MCP.tools):
class SearchAxn
  include Axn
  tool :mcp
  configure(:mcp) do |c|
    c.title = "Item Search"
    c.icons = [{ src: "https://example.com/icon.png", mimeType: "image/png" }]
    c.meta = { version: "1.0" }
  end
  # …
end
```

## Server Context

A tool that needs server-injected data declares the `server_context` ambient field, then declares
each value it needs as a **subfield** of it (`on: :server_context`) — so it reads them like any other
input (no manual digging), and they stay out of `inputSchema`:

```ruby
class AuthenticatedAction
  include Axn

  description "Do something with the current user"

  expects :server_context, on: :ambient_context, type: Object, optional: true
  expects :user, on: :server_context, optional: true    # the value you actually need

  def call
    current_user = user   # resolved from server_context; nil when called without one
    # ...
  end
end
```

`Axn::MCP.wrap` plumbs the `server_context:` kwarg passed to `.call` into `ambient_context:` before
invoking the wrapped Axn — it doesn't inject anything the class didn't ask for. Declaring the field
`on: :ambient_context` is also what keeps it **out of `inputSchema`** (any `on: :ambient_context`
field is excluded automatically, not via a hand-rolled list), and what guarantees an explicit
`server_context:` replaces any process-wide ambient context for that call, so server-side state
can't leak into an MCP invocation. `server_context` (and any subfield of it, like `user`) is `nil`
when the Axn is called directly rather than through the MCP server.

`type: Object` (not `Hash`) is deliberate: `server_context`'s actual class depends on how the tool was invoked and which `mcp` gem version is in use. A direct/test-style call (`Tool.call(server_context: {user_id: 1})`) passes whatever raw value you gave it through, which axn's `ambient_context` resolution wraps in an `ActiveSupport::HashWithIndifferentAccess` if it's a plain `Hash` — `#[]`/`#dig`/`is_a?(Hash)` all work regardless of symbol- or string-keyed access; `instance_of?(Hash)`/`#==` against a literal symbol-keyed `Hash` do not. A real `MCP::Server` round-trip (recent `mcp` gem versions) instead passes an `MCP::ServerContext` object, which is not Hash-like at all but transparently delegates arbitrary method calls — including `#dig`/`#[]` — to whatever context object the server was configured with (`MCP::Server.new(server_context: ...)`) via `method_missing`. Reading with `&.dig(...)`/`&.[]` (rather than asserting a specific class) works uniformly across both cases.

`Axn::MCP.wrap` routes the value in as `ambient_context: { server_context: <value> }` — a *single* ambient field, not spread into top-level ambient fields (so `expects :user_id, on: :ambient_context` wouldn't see it; declare `on: :server_context`). You don't reach into it by hand, though: declaring the values you need as subfields (`expects :user, on: :server_context`) lets axn extract them via `#[]`/`#dig`, which works whether `<value>` is a `Hash` (direct/test calls) or an `MCP::ServerContext` object (a real-server round-trip). `server_context&.dig(...)` still works for ad-hoc/dynamic access, but declared subfields are cleaner and are excluded from `inputSchema` automatically, same as the parent.

### `MCP::ServerContext`'s richer capabilities

When invoked through a real `MCP::Server`, `server_context` (an `MCP::ServerContext`) offers more than `#dig`/`#[]` — session-scoped operations that talk back to the calling client, e.g. `server_context.report_progress(50, total: 100, message: "Halfway done")` or `server_context.cancelled?` inside a long-running `#call`. These work today with no changes needed on this gem's side — `server_context` is just handed through untouched. They're **not available** on a direct/test-style call, where `server_context` is a plain `Hash`/`nil` with no such methods.

The exact method set is entirely the `mcp` gem's own surface and evolves with it (check `MCP::ServerContext`'s own source for your installed version) — some methods there are themselves marked deprecated by the SDK independent of anything in this gem. Consult it directly rather than treating any list here as authoritative.

## Error Handling

Use Axn's standard `fail!` method for controlled failures:

```ruby
def call
  fail! "User not found" unless user
  fail! "Unauthorized" unless authorized?

  # success path...
end
```

The MCP error response carries the Axn's own `result.error` — the gem imposes no headline of its own:

| Failure                                  | Text shown to the LLM   |
| ----------------------------------------- | ----------------------- |
| `fail! "User not found"`                  | `"User not found"`      |
| Bare `fail!`, a validation error, or an unhandled exception | `"Something went wrong"` (axn's generic default) |

Want a friendlier generic message than `"Something went wrong"`? Declare your own base `error "..."`
on the Axn (standard axn practice) — it's per-tool, so each tool can say something specific:

```ruby
class ChargeCard
  include Axn
  error "Could not charge the card"
  # a bare fail! / validation error / exception now surfaces "Could not charge the card"
end
```

With a base `error` declared, an explicit `fail!("reason")` **combines** rather than replaces — by default the base prefixes the reason: `fail!("card declined")` → `"Could not charge the card: card declined"`. (A bare `fail!`, validation error, or exception still surfaces the base alone.) To emit a specific reason *without* the prefix, opt out per-call with `fail!("card declined", standalone: true)` → `"card declined"`. So the table above (reason shown verbatim) reflects a tool with **no** base `error`; add one and reasons are prefixed unless `standalone:`.

Unhandled exceptions are also caught automatically. When an exception occurs:

1. The error is recorded on the result
2. Any configured `on_exception` handlers are triggered (see [Axn configuration](https://github.com/teamshares/axn))
3. An `MCP::Tool::Response` is returned with `error: true`

## Success response text: config and per-tool

By default, successful responses contain a text block with the JSON-serialized `structured_content` (a SHOULD per [MCP spec](https://modelcontextprotocol.io/specification/draft/server/tools#structured-content)). To use the Axn success message instead, set **gem-wide config** once (`Axn::MCP.config.present_as = :message`), override **per tool** via `configure(:mcp)`, or pass it to `wrap`. Valid values are `:structured` (default) and `:message`. Precedence (most local wins): `wrap`'s `present_as:` kwarg → the Axn's own `configure(:mcp)` override → the gem-wide config.

```ruby
# per-tool, on the Axn:
class MyAction
  include Axn
  configure(:mcp) { |c| c.present_as = :message }
end

# or at wrap time:
Axn::MCP.wrap(MyAction, present_as: :message)
```

`configure(:mcp)` uses axn core's namespaced config DSL. The same base Axn can be composed with another adapter (e.g. an `axn-ruby_llm` gem) via its own `config_namespace` — each adapter's settings live in their own namespace, so `configure(:mcp)` and `configure(:other_adapter)` on the same class never collide.

## Integration with MCP Server

Register your tools with an MCP server:

```ruby
require "mcp"
require "axn-mcp"

server = MCP::Server.new(
  name: "my-server",
  version: "1.0.0",
  tools: Axn::MCP.tools,              # or an explicit list: [GreetUserTool, SearchTool, ...]
)

# Use with stdio transport
transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
```

For complete server setup, transport options, and advanced configuration, see the [MCP Ruby SDK documentation](https://github.com/modelcontextprotocol/ruby-sdk).

## Divergences from the raw MCP SDK

`Axn::MCP.wrap` covers the **full `MCP::Tool` configuration surface** — `tool_name`, `title`,
`description`, `icons`, `inputSchema`, `outputSchema`, tool-level `_meta`, and every annotation hint
(`read_only_hint`/`destructive_hint`/`idempotent_hint`/`open_world_hint` + annotation `title`) — plus
`server_context` routing and `MCP::ServerContext`'s session capabilities (`report_progress`,
`cancelled?`, …). Two `MCP::Tool::Response` **output** affordances are intentionally *not* mapped,
because an Axn's model is typed structured I/O:

- **Non-text content.** A wrapped tool's response is always a single text block plus
  `structuredContent` (the JSON of your `exposes`). Image / audio / embedded-resource content
  (`MCP::Content::Image` / `Audio` / `EmbeddedResource`) and multi-block content are not produced —
  an Axn has no convention for declaring "this exposed value is binary/media." For a tool that must
  return media content, register a hand-written `MCP::Tool` directly and splat it alongside
  `Axn::MCP.tools` (see [Mixing with native tools](#mixing-with-native-mcptool-tools)).
- **Response-level `_meta`.** The per-response `_meta` channel isn't populated — there's no Axn
  convention for per-call response metadata; your `exposes` become `structuredContent`. (Tool-*definition*
  `_meta`, in the tools/list entry, *is* supported — via `wrap`'s `meta:` kwarg.)

## Requirements

- Ruby >= 3.2.1
- [axn](https://github.com/teamshares/axn) >= 0.1.0-alpha.4.3, < 0.2.0
- [mcp](https://github.com/modelcontextprotocol/ruby-sdk) >= 0.4, < 1.0 — this range spans versions with
  meaningfully different `server_context` shapes at the transport layer (see [Server Context](#server-context)); this gem is written to be correct across all of it, not just the version you happen to have installed locally.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

Working on this gem with a coding agent? Read [`AGENTS.md`](AGENTS.md) first (`CLAUDE.md` is a
symlink to it).

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/teamshares/axn-mcp](https://github.com/teamshares/axn-mcp).

## Acknowledgments

This gem wraps the excellent [MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk) from the Model Context Protocol team.

<!-- TEMPORARY: transitional upgrade guide — remove this section at 1.0 (tracked in DEPRECATIONS.md). -->
## Upgrading from 0.1.x

`0.2.0` re-architects the gem around author-once (a plain Axn exposed via `Axn::MCP.wrap` / `Axn::MCP.tools`) and retires the `Axn::MCP::Tool` subclass base. The migration is mechanical — mostly one-liners:

| 0.1.x | 0.2.0 |
| --- | --- |
| `class T < Axn::MCP::Tool` … `end` | a plain Axn (`class T; include Axn; … end`), then `Axn::MCP.wrap(T)` |
| `Axn::MCP::Tool.define(description:, expects:, exposes:, …) { … }` | `Axn::MCP.wrap(Axn::Factory.build(expects:, exposes:) { … }, name: "…", description: "…")` |
| `mcp_text_content :message` / `Axn::MCP.config.mcp_text_content` | `present_as` (same `:structured`/`:message` values) — on `configure(:mcp)`, `Axn::MCP.config`, or `wrap(present_as:)` |
| `Axn::MCP.config.error_headline = "…"` | declare a per-tool base `error "…"` on the Axn (MCP errors now surface `result.error`) |
| `read_only!` / `destructive!` / `idempotent!` / `open_world` / `closed_world` | `semantic_hints :read_only, :open_world, …` on the plain Axn |
| a hand-maintained `tools: [T1, T2, …]` array | `tool :mcp` on each Axn + `MCP::Server.new(tools: Axn::MCP.tools)` |

The most common case, before and after:

```ruby
# 0.1.x
class GreetUser < Axn::MCP::Tool
  description "Greet a user"
  expects :name, type: String
  exposes :greeting, type: String
  def call = expose(greeting: "Hello, #{name}!")
end
# registered as: tools: [GreetUser]

# 0.2.0
class GreetUser
  include Axn
  tool :mcp                       # opt into Axn::MCP.tools discovery
  description "Greet a user"
  expects :name, type: String
  exposes :greeting, type: String
  def call = expose(greeting: "Hello, #{name}!")
end
# registered as: tools: Axn::MCP.tools   # or explicitly: [Axn::MCP.wrap(GreetUser)]
```

The retired `Axn::MCP::Tool` / `.define` and the renamed `wrap(mcp_text_content:)` kwarg **raise** with migration messages rather than failing silently, so anything you miss surfaces loudly. See [`DEPRECATIONS.md`](DEPRECATIONS.md) for what's slated for removal at 1.0.
