# Axn::MCP

Build [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) tools using [Axn](https://github.com/teamshares/axn)'s declarative `expects`/`exposes` contract. This gem wraps the official [MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk) and auto-generates JSON schemas from your Axn field declarations.

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

Define an MCP tool by inheriting from `Axn::MCP::Tool`:

```ruby
class GreetUser < Axn::MCP::Tool
  description "Greet a user by name"

  expects :name, type: String, description: "The user's name"
  exposes :greeting, type: String, description: "The greeting message"

  def call
    expose greeting: "Hello, #{name}!"
  end
end
```

That's it. The gem automatically:

- Generates `inputSchema` from your `expects` declarations
- Generates `outputSchema` from your `exposes` declarations
- Converts `Axn::Result` to `MCP::Tool::Response`
- Serializes exposed data to JSON-safe `structured_content`

`inputSchema`/`outputSchema` generation and exposed-value serialization are both sourced from
`axn` core's own reflection APIs (`Axn::Reflection::Schema` and `Axn::Reflection::Values`) — this
gem no longer carries its own schema-building or serialization logic.

## Usage

### Basic Tool Definition

```ruby
class CreateNote < Axn::MCP::Tool
  description "Create a new note"

  expects :title, type: String, description: "Note title"
  expects :content, type: String, description: "Note body"
  expects :tags, type: Array, optional: true, description: "Optional tags"

  exposes :note_id, type: Integer, description: "ID of the created note"

  def call
    note = Note.create!(title:, content:, tags: tags || [])
    expose note_id: note.id
  end
end
```

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

Coercion only affects top-level `expects` fields (not `exposes`, subfields, or `shape:` members), and only converts a non-blank `String` input. An unparseable string doesn't silently pass through to a generic type-mismatch error — it fails validation with a dedicated message: `"<field> could not be coerced to a <Type>"`. `inputSchema`/`outputSchema` output is identical with or without `coerce:` — only accepted inbound values change, not the field's advertised JSON type.


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

(`optional:`/nullable fields reflect as a `type` array, not a bare type.)

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
class UpdateUser < Axn::MCP::Tool
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

### Annotations

Declare `axn` core's generic `semantic_hints` DSL (`semantic_hints :read_only, :idempotent, ...`) and this gem maps them to MCP annotations automatically. This gem registers `:open_world`/`:closed_world` as additional semantic hints (via `Axn.extension_config.register_semantic_hint` — no core change needed for MCP-only vocabulary):

| Declared `semantic_hints` | Default annotation      |
| -------------------------- | ------------------------ |
| `:read_only`                | `read_only_hint: true`, `destructive_hint: false` |
| `:idempotent`               | `idempotent_hint: true`  |
| `:destructive`              | `destructive_hint: true` |
| `:open_world`               | `open_world_hint: true`  |
| `:closed_world`             | `open_world_hint: false` |

```ruby
class ReadOnlyTool < Axn::MCP::Tool
  description "Fetch data without side effects"
  semantic_hints :read_only, :closed_world
  # annotations now include read_only_hint: true, destructive_hint: false, open_world_hint: false

  # ...
end
```

`open_world`/`closed_world` (no bang) are shorthand for declaring just that one hint:

```ruby
class DangerousTool < Axn::MCP::Tool
  description "Delete all the things"
  semantic_hints :destructive, :idempotent
  open_world # equivalent to: semantic_hints(*(semantic_hints + [:open_world]))

  # ...
end
```

For anything `semantic_hints` doesn't cover (a custom `title:`, or an annotation with no corresponding hint), set `annotations(...)` directly:

```ruby
class CustomAnnotations < Axn::MCP::Tool
  annotations(
    read_only_hint: true,
    idempotent_hint: true,
    title: "My Custom Tool",
  )

  # ...
end
```

An explicit `annotations(...)` call always wins over hint-derived defaults, on this class or any ancestor. `semantic_hints`-derived annotations are re-derived from the full set of declared hints each time (so declaring `:open_world` and later `:closed_world` ends with only `open_world_hint: false` applied, not both), and a subclass that inherits `semantic_hints` from a base class without redeclaring them still gets the right annotations.

> **Deprecated:** `read_only!`/`destructive!`/`idempotent!`/`open_world!`/`closed_world!` (bang methods) still work, as thin aliases over `semantic_hints` — but emit a deprecation warning and will be removed in a future release. Prefer `semantic_hints`/`open_world`/`closed_world` directly, as shown above.


### Factory-Style Definition

For quick one-off tools:

```ruby
SearchTool = Axn::MCP::Tool.define(
  description: "Search for items",
  expects: { query: { type: String, description: "Search query" } },
  exposes: { results: { type: Array } },
  annotations: { read_only_hint: true },
) do
  expose results: Item.search(query)
end
```

### Wrapping a Plain Axn with `Axn::MCP.wrap`

If you already have an Axn action that doesn't subclass `Axn::MCP::Tool` — and you don't want it to, e.g. because it's shared with non-MCP callers — expose it as an `::MCP::Tool` with `Axn::MCP.wrap` instead of rewriting it:

```ruby
class GreetPlainly
  include Axn

  expects :name, type: String
  expects :server_context, on: :ambient_context, type: Object, optional: true
  exposes :greeting, type: String

  def call
    expose greeting: "Hello, #{name}! (user #{server_context&.dig(:user_id).inspect})"
  end
end

GreetPlainlyTool = Axn::MCP.wrap(GreetPlainly, description: "Greets someone")
```

`GreetPlainly` itself is untouched: `GreetPlainly.call(name: "Alice")` still returns a plain `Axn::Result`, with no MCP awareness at all. `Axn::MCP.wrap` generates a *separate* `::MCP::Tool` subclass that carries all the MCP transport concerns (schema, `server_context` routing, response mapping) via the same path `Axn::MCP::Tool#call` itself uses:

```ruby
GreetPlainlyTool.input_schema_value.to_h[:properties].keys # => [:name] (server_context excluded)
GreetPlainlyTool.call(name: "Bob", server_context: { user_id: 42 }) # => MCP::Tool::Response
```

If a wrapped Axn needs server-injected data, it must declare the field itself, the same way `Axn::MCP::Tool` does — `expects :server_context, on: :ambient_context, type: Object` (not, say, `expects :user_id, on: :ambient_context` directly) — and read it with the same `server_context&.dig(...)` convention used throughout this README. `Axn::MCP.wrap` doesn't inject anything the wrapped class didn't ask for; it just plumbs the `server_context:` kwarg passed to `.call` into `ambient_context:` before invoking the wrapped Axn.

`wrap` also accepts `name:`, `annotations:`, and `mcp_text_content:` (defaulting to the gem-wide `Axn::MCP.config.mcp_text_content`) — `annotations:`/`mcp_text_content:` mirror `Tool.define`'s own options of the same name, but `name:` is `wrap`-specific: `Tool.define` has no equivalent (it takes no `name:` option; a factory tool's MCP name is derived from the anonymous class as usual).

Unlike `Axn::MCP::Tool`, the generated subclass itself has no dual-mode: its `.call` always returns
`MCP::Tool::Response`, never a raw `Axn::Result` (that's still true only of the *original*,
untouched class). For the same reason, the generated subclass has no `.call!` either — a bang
method that just delegated to `.call` would promise raise-on-failure semantics it doesn't deliver;
if you want real bang semantics, call the original wrapped class's own `.call!` directly.

### Server Context

`server_context` is automatically available in all tools (no declaration needed):

```ruby
class AuthenticatedTool < Axn::MCP::Tool
  description "Do something with the current user"

  def call
    current_user = server_context&.dig(:user)
    # ...
  end
end
```

Note the safe navigation (`&.dig`): `server_context` may be `nil` if the tool is invoked directly as a standard Axn action rather than through the MCP server.

The `server_context` field is excluded from the generated `inputSchema` since it's injected by the MCP server, not provided by the LLM. Under the hood, `Axn::MCP::Tool` declares `expects :server_context, on: :ambient_context, type: Object, optional: true` and routes the value passed to `.call(server_context: ...)` through `axn` core's `ambient_context` mechanism — this is also what keeps it out of `inputSchema` (any `on: :ambient_context` field is excluded automatically, not via a hand-rolled list) and what guarantees an explicit `server_context:` replaces any process-wide ambient context for that call, so server-side state can't leak into an MCP invocation.

`type: Object` (not `Hash`) is deliberate: `server_context`'s actual class depends on how the tool was invoked and which `mcp` gem version is in use. A direct/test-style call (`Tool.call(server_context: {user_id: 1})`) passes whatever raw value you gave it through, which axn's `ambient_context` resolution wraps in an `ActiveSupport::HashWithIndifferentAccess` if it's a plain `Hash` — `#[]`/`#dig`/`is_a?(Hash)` all work regardless of symbol- or string-keyed access; `instance_of?(Hash)`/`#==` against a literal symbol-keyed `Hash` do not. A real `MCP::Server` round-trip (recent `mcp` gem versions) instead passes an `MCP::ServerContext` object, which is not Hash-like at all but transparently delegates arbitrary method calls — including `#dig`/`#[]` — to whatever context object the server was configured with (`MCP::Server.new(server_context: ...)`) via `method_missing`. Reading with `&.dig(...)`/`&.[]` (rather than asserting a specific class) works uniformly across both cases.

### Dual-Use: MCP Server vs Direct Invocation

Tools automatically adapt their return type based on how they're called:

```ruby
# Called FROM MCP server (server_context injected) → returns MCP::Tool::Response
# This happens automatically when registered with MCP::Server

# Called DIRECTLY without server_context → returns Axn::Result
result = MyTool.call(name: "Alice")
if result.ok?
  puts result.greeting
else
  puts "Error: #{result.message}"
end

# Or use call! to raise on failure
result = MyTool.call!(name: "Bob")
puts result.greeting
```

The branching is based on presence of `server_context`:

- **With `server_context`**: Returns `MCP::Tool::Response` (for MCP server compatibility)
- **Without `server_context`**: Returns `Axn::Result` (standard Axn semantics)

This allows you to test tools or call them from non-MCP contexts using standard Axn patterns.

## Error Handling

Use Axn's standard `fail!` method for controlled failures:

```ruby
def call
  fail! "User not found" unless user
  fail! "Unauthorized" unless authorized?

  # success path...
end
```

`Axn::MCP::Tool` declares a base error headline (default `"Tool call failed"`), so the text the
LLM actually sees is:

| Failure                                  | Text shown to the LLM                |
| ----------------------------------------- | ------------------------------------- |
| `fail! "User not found"`                  | `"Tool call failed: User not found"`  |
| Bare `fail!`, a validation error, or an unhandled exception | `"Tool call failed"`                  |

Change the headline **gem-wide** with `Axn::MCP.config.error_headline = "Something broke"` — it's
read fresh on every failure, so there's no reload or require-order gotcha. Override it **per tool**
by declaring your own base `error "..."` on the subclass (which wins over the configured headline),
or opt a single message out of prefixing with `fail!("...", standalone: true)`.

Unhandled exceptions are also caught automatically. When an exception occurs:

1. The error is recorded on the result
2. Any configured `on_exception` handlers are triggered (see [Axn configuration](https://github.com/teamshares/axn))
3. An `MCP::Tool::Response` is returned with `error: true`

Both `fail!` calls and unhandled exceptions result in error responses to the LLM. Calling a tool
directly with `call!` on a `fail!` raises `Axn::Failure` whose `#message` matches `result.error` —
i.e. the same prefixed text. For an unhandled exception, `call!` re-raises the *original* exception
with its original `#message`, which is not the prefixed headline shown to the LLM via `result.error`.

## Integration with MCP Server

Register your tools with an MCP server:

```ruby
require "mcp"
require "axn-mcp"

server = MCP::Server.new(
  name: "my-server",
  version: "1.0.0",
  tools: [GreetUser, CreateNote, SearchTool],
)

# Use with stdio transport
transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
```

For complete server setup, transport options, and advanced configuration, see the [MCP Ruby SDK documentation](https://github.com/modelcontextprotocol/ruby-sdk).

### Success response text: config and per-tool

By default, successful responses contain a text block with the JSON-serialized `structured_content` (a SHOULD per [MCP spec](https://modelcontextprotocol.io/specification/draft/server/tools#structured-content)). To use the Axn success message instead, set **central config** once (`Axn::MCP.config.mcp_text_content = :message`) or override **per tool** with `mcp_text_content :message`. Valid values are `:structured` (default) and `:message`; per-tool overrides config.

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
