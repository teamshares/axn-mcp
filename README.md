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
    "timeout": { "type": "integer" }
  }
}
```

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
    "active":        { "type": "boolean" },
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
{ "type": "array", "items": { "anyOf": [{ "type": "string" }, { "type": "number" }] } }
```

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
      "active":        { "type": "boolean" },
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
      "type": "integer",
      "description": "ID of the User record"
    }
  }
}
```

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

Use convenience methods or the `annotations` DSL:

```ruby
class ReadOnlyTool < Axn::MCP::Tool
  description "Fetch data without side effects"
  read_only!

  # ...
end

class DangerousTool < Axn::MCP::Tool
  description "Delete all the things"
  destructive!
  idempotent!

  # ...
end

class CustomAnnotations < Axn::MCP::Tool
  annotations(
    read_only_hint: true,
    idempotent_hint: true,
    title: "My Custom Tool",
  )

  # ...
end
```

Available shortcuts:


| Method          | Effect                                            |
| --------------- | ------------------------------------------------- |
| `read_only!`    | `read_only_hint: true`, `destructive_hint: false` |
| `destructive!`  | `destructive_hint: true`, `read_only_hint: false` |
| `idempotent!`   | `idempotent_hint: true`                           |
| `open_world!`   | `open_world_hint: true`                           |
| `closed_world!` | `open_world_hint: false`                          |


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

The `server_context` field is excluded from the generated `inputSchema` since it's injected by the MCP server, not provided by the LLM.

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

Unhandled exceptions are also caught automatically. When an exception occurs:

1. The error is recorded on the result
2. Any configured `on_exception` handlers are triggered (see [Axn configuration](https://github.com/teamshares/axn))
3. An `MCP::Tool::Response` is returned with `error: true`

Both `fail!` calls and unhandled exceptions result in error responses to the LLM.

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
- [axn](https://github.com/teamshares/axn) >= 0.1.0-alpha.4.3
- [mcp](https://github.com/modelcontextprotocol/ruby-sdk) >= 0.4

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/teamshares/axn-mcp](https://github.com/teamshares/axn-mcp).

## Acknowledgments

This gem wraps the excellent [MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk) from the Model Context Protocol team.
