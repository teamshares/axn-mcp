# PRO-2844: Adopt core reflection + register MCP adapter via extension registry

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consume the JSON-schema reflection, exposed-value serialization, semantic-hints, and
ambient-context primitives that PRO-2842 landed in `axn` core; delete axn-mcp's hand-rolled
equivalents; add `Axn::MCP.wrap(any_axn)` so a plain Axn (not subclassing `Axn::MCP::Tool`) can be
exposed as an `::MCP::Tool`; keep `Axn::MCP::Tool` working unchanged for existing subclasses.

**Architecture:** `Axn::MCP::Tool` stops hand-building JSON Schema / serializing exposed values —
it delegates to `Axn::Reflection::Schema`/`Axn::Reflection::Values` (now vendored in axn core, a
strict superset of the deleted `Axn::MCP::SchemaBuilder`/parts of `Axn::MCP::Serializer`). A new
`Axn::MCP.wrap(axn_class, description:, **opts)` factory builds an anonymous `::MCP::Tool`
subclass around *any* Axn, extracting the "map `server_context:` → `ambient_context:`, call the
Axn, map `Axn::Result` → `MCP::Tool::Response`" logic that `Axn::MCP::Tool#call` already does
today into a shared `Axn::MCP::Invocation.perform` helper both paths call — so `Tool.call`'s
existing dual-mode (`Axn::Result` vs `MCP::Tool::Response`, branching on `server_context:`
presence) keeps working byte-for-byte, while `wrap` covers the new plain-Axn case. MCP-only
annotation vocabulary (`open_world`/`closed_world`) is added via core's new
`Axn.extension_config.register_semantic_hint` registry — no core changes required to add them.

**Tech Stack:** Ruby, RSpec, the `axn` gem (git `main`, commit `9faec17` — "DRY the tool concept
into axn core"), the `mcp` gem (`ruby-sdk`, v0.7.1).

## Global Constraints

- `bundle exec rspec` and `bundle exec rubocop` must pass after every task (per `AGENTS.md`).
- Never break the `server_context:`-presence branch in `Axn::MCP::Tool.call` — existing consumers
  (7 tools in `os-app`, `lib/mcp/tools/*_tool.rb`) call it both ways on the *same* class.
- Pin exact user-facing strings/shapes with specs, not `be_present`/`ok?` — verify schema output
  against real `MCP::Tool::Response`/`InputSchema`/`OutputSchema` objects, not hand-built hashes.
- TDD: write/adjust the failing spec before touching implementation, for every task.
- `CHANGELOG.md` entry + `lib/axn/mcp/version.rb` bump (semver) per user-visible change — this is a
  breaking internal refactor with a preserved public surface, so bump appropriately (see Task 9).
- Update `README.md` wherever consumer-visible behavior changes (schema shape, `wrap` API).
- Do not rename the existing `Axn::MCP.config.mcp_text_content` setting or its per-tool
  `mcp_text_content(...)` override DSL — `os-app`'s tools may already reference it by that name,
  and the ticket's "text_content (a.k.a. today's mcp_text_content)" is describing the *existing*
  `Axn::Configurable`-backed override mechanism, not asking for a rename.

---

## Background: what changed in `axn` core (already researched, do not re-derive)

Bundled via `bundle update axn` (Gemfile already pins `github: "teamshares/axn", branch: "main"`).
Local gem path: `/Users/kali/.asdf/installs/ruby/3.2.2/lib/ruby/gems/3.2.0/bundler/gems/axn-9faec1705d7e`.

Every `Axn` (via `include Axn`) now automatically gets:

- `SomeAxn.input_schema` / `SomeAxn.output_schema` (**zero-arg**, from
  `Axn::Core::SchemaReflection`, `lib/axn/core/schema_reflection.rb`) — return plain Hashes built
  by `Axn::Reflection::Schema.build_input(internal_field_configs, subfield_configs)` /
  `.build_output(external_field_configs)` (`lib/axn/reflection/schema.rb`). Signature-compatible
  drop-in for `Axn::MCP::SchemaBuilder.build_input`/`.build_output`, but stricter/more correct
  (`anyOf` unions, nullability folding as `type: [X, "null"]`, deep-copied enum/default literals).
  **Note:** `Axn::MCP::Tool < ::MCP::Tool` already defines its own `input_schema`/`output_schema`
  *directly on the class* (get-or-set, `NOT_SET`-sentinel style, wrapping `::MCP::Tool::InputSchema`)
  — that direct definition always wins method-resolution over both the extended
  `Core::SchemaReflection::ClassMethods` and the inherited `::MCP::Tool` accessor, so there's no
  naming collision in practice. Inside Tool's own method bodies, call
  `Axn::Reflection::Schema.build_input(...)`/`.build_output(...)` directly — do not rely on `super`
  (arities differ: 0 vs 1, and the ancestor order isn't worth depending on).
- `Axn::Reflection::Values.serialize_exposed(result, field_configs)` /
  `.serialize_value(value)` (`lib/axn/reflection/values.rb`) — drop-in replacement for
  `Axn::MCP::Serializer.serialize_exposed`/`.serialize_value`, plus richer coercion (Symbol→String,
  BigDecimal/Rational→Float, Time/Date/DateTime→iso8601).
- `ambient_context` (`Axn::Core::AmbientContext`, `lib/axn/core/ambient_context.rb`) — a reserved,
  always-present parent field. Subfields are declared `expects :x, on: :ambient_context`. Resolution
  order: an explicit `ambient_context:` kwarg passed to `.call` **replaces** (never merges with) the
  configured `Axn.config.ambient_context_provider` / `ActiveSupport::CurrentAttributes` default —
  this is what stops server-side `Current` state leaking into MCP calls. `ambient_context` itself is
  excluded from `input_schema` (`Axn::Reflection::Schema::EXCLUDED_FROM_INPUT_SCHEMA = %i[ambient_context]`)
  and, because only *top-level* fields become schema properties, its subfields (like a
  `server_context` subfield) are automatically never surfaced either — no per-adapter exclusion list
  needed.
- `semantic_hints(*hints)` (`Axn::Core::SemanticHints`, `lib/axn/core/semantic_hints.rb`) — class
  DSL; no-arg call reads back `_semantic_hints` (default `[]`); called with symbols validates
  against `Axn.extension_config.registered_semantic_hints` (built-in: `:read_only`, `:idempotent`,
  `:destructive`) and raises `ArgumentError` on unknown hints.
- `Axn.extension_config.register_semantic_hint(*hints)` (`Axn::ExtensionConfig`,
  `lib/axn/extension_config.rb`) — adapters extend the vocabulary. This is how axn-mcp adds
  `:open_world`/`:closed_world` without any core change.
- `extension_metadata(:adapter)` / `set_extension_metadata(:adapter, **kwargs)`
  (`Axn::Core::ExtensionMetadata`) — a per-adapter, inherited, copy-on-write Hash bag. Not used by
  this plan (axn-mcp's existing `Axn::Configurable`-backed `mcp_text_content` override already
  covers the same need), but available if a future task needs it.
- **Does NOT exist:** any `Axn::Outcome` concept or generic `Result` → adapter-response mapper.
  `Axn::MCP::Serializer.result_to_mcp_response` (the `Axn::Result` → `MCP::Tool::Response` mapping)
  has no core equivalent and stays in axn-mcp.
- **Does NOT exist:** any change to `Axn::Factory` or a delegation from `Axn::MCP::Tool.define` to
  it — `Tool.define` (`lib/axn/mcp/tool.rb:121-141`) stays as its own independent implementation.

`::MCP::Tool` (`mcp` gem, `lib/mcp/tool.rb`) relevant facts used below:
- `input_schema(value = NOT_SET)` / `output_schema(value = NOT_SET)` accept either a Hash or an
  `InputSchema`/`OutputSchema` instance when setting — passing a plain Hash works.
- `annotations(hash = NOT_SET)` **fully replaces** `@annotations_value` each call (constructs a new
  `Annotations.new(**hash)`) — it does not merge with a previous call. `Annotations.new` defaults:
  `destructive_hint: true, idempotent_hint: false, open_world_hint: true, read_only_hint: false`.
  Existing `Axn::MCP::Tool.read_only!`/`.destructive!`/etc. rely on this full-replace behavior and
  must keep doing so verbatim (Task 8 adds a *new*, independent semantic-hints-driven default that
  only applies when `annotations(...)` was never called explicitly).

---

## File Structure

- Modify `lib/axn/mcp.rb` — register `:open_world`/`:closed_world` semantic hints at load; update
  `require_relative` list (drop `schema_builder`, add `annotations`, `invocation`, `wrap`).
- Delete `lib/axn/mcp/schema_builder.rb` — superseded by `Axn::Reflection::Schema`.
- Modify `lib/axn/mcp/serializer.rb` — drop `serialize_exposed`/`serialize_value` (delegate call
  sites to `Axn::Reflection::Values`), keep `result_to_mcp_response`/`success_response_text`.
- Create `lib/axn/mcp/annotations.rb` — hint↔annotation vocabulary + mapping function, used by both
  the legacy bang-methods and the new semantic-hints-driven default.
- Create `lib/axn/mcp/invocation.rb` — shared `server_context:` → `ambient_context:` → call → map
  logic, used by both `Axn::MCP::Tool.call` and `Axn::MCP.wrap`-generated classes.
- Create `lib/axn/mcp/wrap.rb` — `Axn::MCP.wrap(axn_class, description:, **opts)`.
- Modify `lib/axn/mcp/tool.rb` — swap schema builder calls to `Axn::Reflection::Schema`; move
  `server_context` to an `ambient_context` subfield; delegate invocation to `Invocation.perform`;
  add semantic-hints → annotations default; keep `read_only!` etc. as thin back-compat aliases; add
  `open_world`/`closed_world` (new, semantic-hints-registry-backed) alongside the existing
  `open_world!`/`closed_world!` bang methods (unchanged).
- Delete `spec/axn/mcp/schema_builder_spec.rb` — retarget its scenarios into
  `spec/axn/mcp/tool_spec.rb`'s existing schema section (it already builds `Tool` subclasses per
  scenario; this is the "verify against real objects" path AGENTS.md requires).
- Modify `spec/axn/mcp/serializer_spec.rb` — drop the `.serialize_value`/`.serialize_exposed`
  examples (now core's responsibility, covered by axn's own test suite), keep
  `.result_to_mcp_response` examples.
- Create `spec/axn/mcp/annotations_spec.rb`, `spec/axn/mcp/wrap_spec.rb`.
- Modify `spec/axn/mcp/tool_spec.rb`, `spec/integration/server_integration_spec.rb` — update
  `server_context`-related expectations if any assert on `internal_field_configs` shape directly.
- Modify `CHANGELOG.md`, `lib/axn/mcp/version.rb`, `README.md`.

---

### Task 1: Register MCP-only semantic hints (`open_world`/`closed_world`)

**Files:**
- Create: `lib/axn/mcp/annotations.rb`
- Modify: `lib/axn/mcp.rb`
- Test: `spec/axn/mcp/annotations_spec.rb`

**Interfaces:**
- Produces: `Axn::MCP::Annotations.annotations_for(hints)` — `Array<Symbol> -> Hash` (MCP
  annotation kwargs, e.g. `{read_only_hint: true}`), used by Task 8.
- Produces: `Axn.extension_config.registered_semantic_hints` includes `:open_world`, `:closed_world`
  after `require "axn/mcp"`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/axn/mcp/annotations_spec.rb
# frozen_string_literal: true

RSpec.describe Axn::MCP::Annotations do
  describe "registered vocabulary" do
    it "extends axn core's semantic hint registry with MCP-only hints" do
      expect(Axn.extension_config.registered_semantic_hints).to include(:open_world, :closed_world)
    end

    it "keeps axn core's built-in hints registered too" do
      expect(Axn.extension_config.registered_semantic_hints).to include(:read_only, :idempotent, :destructive)
    end
  end

  describe ".annotations_for" do
    it "maps read_only to read_only_hint: true" do
      expect(described_class.annotations_for([:read_only])).to eq(read_only_hint: true)
    end

    it "maps idempotent to idempotent_hint: true" do
      expect(described_class.annotations_for([:idempotent])).to eq(idempotent_hint: true)
    end

    it "maps destructive to destructive_hint: true" do
      expect(described_class.annotations_for([:destructive])).to eq(destructive_hint: true)
    end

    it "maps open_world to open_world_hint: true" do
      expect(described_class.annotations_for([:open_world])).to eq(open_world_hint: true)
    end

    it "maps closed_world to open_world_hint: false" do
      expect(described_class.annotations_for([:closed_world])).to eq(open_world_hint: false)
    end

    it "combines multiple hints into one hash" do
      expect(described_class.annotations_for(%i[read_only idempotent])).to eq(
        read_only_hint: true, idempotent_hint: true,
      )
    end

    it "returns an empty hash for no hints" do
      expect(described_class.annotations_for([])).to eq({})
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/axn/mcp/annotations_spec.rb`
Expected: FAIL — `uninitialized constant Axn::MCP::Annotations`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/axn/mcp/annotations.rb
# frozen_string_literal: true

module Axn
  module MCP
    # Maps axn core's `semantic_hints` vocabulary (plus the MCP-only extensions this adapter
    # registers below) to MCP tool annotation kwargs. Registering :open_world/:closed_world via
    # Axn.extension_config.register_semantic_hint is the poster-child use of PRO-2842's registry:
    # no core change was needed to add MCP-spec-only vocabulary.
    module Annotations
      HINT_TO_ANNOTATION = {
        read_only: { read_only_hint: true },
        idempotent: { idempotent_hint: true },
        destructive: { destructive_hint: true },
        open_world: { open_world_hint: true },
        closed_world: { open_world_hint: false },
      }.freeze

      module_function

      def annotations_for(hints)
        hints.each_with_object({}) { |hint, acc| acc.merge!(HINT_TO_ANNOTATION.fetch(hint, {})) }
      end
    end
  end
end
```

```ruby
# lib/axn/mcp.rb — add after `require "mcp"`, before the settings block
Axn.extension_config.register_semantic_hint(:open_world, :closed_world)
```

Also add `require_relative "mcp/annotations"` to the require list (before `mcp/tool`, since Task 8
will reference it from `tool.rb`).

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/axn/mcp/annotations_spec.rb`
Expected: PASS (8 examples)

- [ ] **Step 5: Commit**

```bash
git add lib/axn/mcp.rb lib/axn/mcp/annotations.rb spec/axn/mcp/annotations_spec.rb
git commit -m "PRO-2844: Register open_world/closed_world via core's semantic-hints registry"
```

---

### Task 2: Delegate exposed-value serialization to core's `Axn::Reflection::Values`

**Files:**
- Modify: `lib/axn/mcp/serializer.rb`
- Modify: `spec/axn/mcp/serializer_spec.rb`

**Interfaces:**
- Consumes: `Axn::Reflection::Values.serialize_exposed(result, field_configs)`,
  `Axn::Reflection::Values.serialize_value(value)` (from `axn` core, already loaded transitively via
  `require "axn"` in `lib/axn/mcp.rb`).
- Produces: `Axn::MCP::Serializer.result_to_mcp_response(result, field_configs, text_content:)`
  unchanged signature/behavior (Task 3+ callers keep using this).

- [ ] **Step 1: Write the failing test**

Delete the `.serialize_value` and `.serialize_exposed` `describe` blocks from
`spec/axn/mcp/serializer_spec.rb` (lines 4–83 as of this writing — the two top `describe` blocks),
keeping only the `.result_to_mcp_response` block. Add one new example proving the delegation:

```ruby
# spec/axn/mcp/serializer_spec.rb — replace the deleted blocks with:
RSpec.describe Axn::MCP::Serializer do
  describe ".result_to_mcp_response" do
    it "serializes exposed values the same way Axn::Reflection::Values does" do
      config = Struct.new(:field).new(:count)
      result = double(ok?: true, count: 42, message: "done")

      response = described_class.result_to_mcp_response(result, [config], text_content: :structured)

      expect(response.structured_content).to eq(Axn::Reflection::Values.serialize_exposed(result, [config]))
    end

    # ... (keep all pre-existing .result_to_mcp_response examples verbatim below this point)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/axn/mcp/serializer_spec.rb`
Expected: initially PASSES (implementation hasn't changed yet) — this step is a no-op gate here
because we're deleting redundant coverage rather than adding new failing behavior. Confirm instead
that the full file still passes after the deletions, before touching `serializer.rb`:
Expected: PASS, fewer examples than before.

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/axn/mcp/serializer.rb
# frozen_string_literal: true

require "json"
require "active_support/core_ext/object/blank"

module Axn
  module MCP
    module Serializer
      module_function

      def result_to_mcp_response(result, field_configs, text_content: :structured)
        if result.ok?
          exposed = Axn::Reflection::Values.serialize_exposed(result, field_configs)
          success_text = success_response_text(result, exposed, text_content)
          ::MCP::Tool::Response.new(
            [{ type: "text", text: success_text }],
            structured_content: exposed.presence,
          )
        else
          ::MCP::Tool::Response.new(
            [{ type: "text", text: result.error }],
            error: true,
          )
        end
      end

      def success_response_text(result, exposed, text_content)
        use_message = text_content == :message
        success_message = result.respond_to?(:success) ? result.success : result.message
        if use_message || exposed.blank?
          success_message
        else
          JSON.generate(exposed)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/axn/mcp/serializer_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/axn/mcp/serializer.rb spec/axn/mcp/serializer_spec.rb
git commit -m "PRO-2844: Delegate exposed-value serialization to Axn::Reflection::Values"
```

---

### Task 3: Delegate schema building to core's `Axn::Reflection::Schema`; delete `SchemaBuilder`

**Files:**
- Modify: `lib/axn/mcp/tool.rb`
- Delete: `lib/axn/mcp/schema_builder.rb`
- Delete: `spec/axn/mcp/schema_builder_spec.rb`
- Modify: `lib/axn/mcp.rb` (drop `require_relative "mcp/schema_builder"`)
- Modify: `spec/axn/mcp/tool_spec.rb` (schema-shape assertions, if the swap changes output)

**Interfaces:**
- Consumes: `Axn::Reflection::Schema.build_input(field_configs, subfield_configs = [])`,
  `Axn::Reflection::Schema.build_output(field_configs)` (both return plain Hashes, same shape as the
  deleted `SchemaBuilder`'s methods plus core's documented improvements — nullable fields now emit
  `type: [X, "null"]`; boolean fields emit `type: "boolean", enum: [true]` or `[false]` instead of a
  bare `"boolean"`).
- Produces: `Axn::MCP::Tool.input_schema`/`.output_schema` unchanged public signature (get-or-set,
  `NOT_SET` sentinel, wraps `::MCP::Tool::InputSchema`/`OutputSchema`).

- [ ] **Step 1: Update the call sites (still calling the soon-to-be-deleted `SchemaBuilder`, to
      isolate this as a pure "swap the builder" change before deleting the old spec file)**

```ruby
# lib/axn/mcp/tool.rb — swap SchemaBuilder for Axn::Reflection::Schema in input_schema/output_schema
def input_schema(value = NOT_SET)
  if value != NOT_SET
    super
  elsif @input_schema_value
    @input_schema_value
  else
    @input_schema_value = ::MCP::Tool::InputSchema.new(
      Axn::Reflection::Schema.build_input(internal_field_configs, subfield_configs),
    )
  end
end
```

```ruby
def output_schema(value = NOT_SET)
  if value != NOT_SET
    super
  elsif @output_schema_value
    @output_schema_value
  elsif external_field_configs.empty?
    nil
  else
    @output_schema_value = ::MCP::Tool::OutputSchema.new(
      Axn::Reflection::Schema.build_output(external_field_configs),
    )
  end
end
```

- [ ] **Step 2: Run the full existing schema suite against the new builder, un-skipped, to see what
      actually differs**

Run: `bundle exec rspec spec/axn/mcp/schema_builder_spec.rb spec/axn/mcp/tool_spec.rb`
Expected: FAIL on some examples — core's builder is stricter (nullability becomes a `type` array,
boolean fields gain an `enum: [true]`/`[false]` instead of a bare `"boolean"` type, unions may
appear as `anyOf`). Read each failure's actual/expected diff and confirm it matches the documented
behavior in `axn/reflection/schema.rb` (comments cited in the Background section above) before
touching an expectation — the divergence is intentional/correct, not a bug to work around.

- [ ] **Step 3: Retarget `schema_builder_spec.rb`'s scenarios into `tool_spec.rb`, deleting the
      standalone file**

For every `describe`/`it` block in `spec/axn/mcp/schema_builder_spec.rb` that has no equivalent
already in `spec/axn/mcp/tool_spec.rb`'s schema section, port it: replace
`described_class.build_input(tool.internal_field_configs)` with a real `Tool` subclass's
`.input_schema_value.to_h[:properties]` (or `.output_schema_value`), so the assertion exercises the
actual `MCP::Tool::InputSchema`/`OutputSchema` objects per `AGENTS.md`'s rule, not a bare Hash.
Update each expected Hash to match Step 2's confirmed-correct actual output. Example port:

```ruby
# spec/axn/mcp/tool_spec.rb — inside the existing schema describe block
it "reflects a nullable field as a type array, not a bare boolean" do
  tool = Class.new(Axn::MCP::Tool) do
    expects :active, type: :boolean, allow_nil: true
    def call = nil
  end

  properties = tool.input_schema_value.to_h[:properties]
  expect(properties[:active][:type]).to eq(["boolean", "null"])
end
```

Delete `spec/axn/mcp/schema_builder_spec.rb` and `lib/axn/mcp/schema_builder.rb` once every scenario
has a home. Remove `require_relative "mcp/schema_builder"` from `lib/axn/mcp.rb`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/axn/mcp/tool_spec.rb`
Expected: PASS, no reference to `Axn::MCP::SchemaBuilder` remains anywhere (`grep -rn SchemaBuilder lib spec` returns nothing).

- [ ] **Step 5: Commit**

```bash
git add lib/axn/mcp.rb lib/axn/mcp/tool.rb spec/axn/mcp/tool_spec.rb
git rm lib/axn/mcp/schema_builder.rb spec/axn/mcp/schema_builder_spec.rb
git commit -m "PRO-2844: Delegate schema building to Axn::Reflection::Schema; delete SchemaBuilder"
```

---

### Task 4: Fix pre-existing `description` class-method collision from the axn core bump

**Context (why this task exists — not in the original ticket, discovered mid-implementation):**
Task 3's implementer found that `bundle exec rspec` had 3 pre-existing failures unrelated to
schema building, and confirmed via a clean isolated check (same `mcp` gem version, same `axn`
revision, checked out at the commit immediately after `bundle update axn` and before any of
Tasks 1-3) that these failures predate this entire plan — they're a direct regression from
adopting the new `axn` core version. Since every `Tool` subclass's `description "..."` DSL call is
foundational (used pervasively, including by every scenario in this plan's own specs and
presumably by all 7 `os-app` tools), this must be fixed before Task 9's "full suite green" gate,
even though it isn't one of the ticket's 5 scope items.

**Root cause:** `axn` core's `Axn::Core::Naming` module (`lib/axn/core/naming.rb`, mixed into every
Axn via `include Axn`) defines its own class method `description(value = NOT_SET)` — same
get-or-set signature style as `::MCP::Tool`'s, but it stores into a *different* place
(`_axn_description`, an axn-internal display concept unrelated to MCP transport). Because
`include Axn` `extend`s `Naming::ClassMethods` directly onto `Axn::MCP::Tool`'s singleton class,
and `Axn::MCP::Tool` itself has never redefined `description` directly (unlike `input_schema`/
`output_schema`, which the class already redefines), method resolution for
`SomeTool.description("...")` now hits `Naming::ClassMethods#description` first, silently
shadowing `::MCP::Tool`'s own `description(value)` setter. The description string a tool declares
never reaches `@description_value`, so `to_h[:description]` (what the MCP transport/server actually
sends) is `nil`.

**Files:**
- Modify: `lib/axn/mcp/tool.rb`
- Test: `spec/axn/mcp/tool_spec.rb` (a description-focused example already exists and currently
  fails — e.g. the `.to_h` "includes auto-generated schemas in MCP format" example and the
  `.define` example; both assert on a description string round-tripping to `to_h`/`description_value`)

**Interfaces:**
- Produces: `Axn::MCP::Tool.description(value = NOT_SET)` — get-or-set, delegates to `::MCP::Tool`'s
  own `@description_value`-backed accessor (bypassing the shadowing `Axn::Core::Naming` method),
  identical behavior to what existed before the `axn` core bump.

- [ ] **Step 1: Confirm the failing tests and their exact current failure**

Run: `bundle exec rspec spec/axn/mcp/tool_spec.rb spec/integration/server_integration_spec.rb`
Expected: FAIL — at minimum these two (there may be a third depending on what Task 3 left in
place): `Axn::MCP::Tool.to_h includes auto-generated schemas in MCP format` (expected a description
string, got `nil`) and `Axn::MCP::Tool.define creates a tool class with expects/exposes` (same
shape of failure). These are NOT new tests to write — they already exist in the spec suite and are
currently failing; this task's job is to make them pass again, not to author new coverage. If you
want one more explicit unit test pinning the fix, add it near the existing schema/description specs
in `tool_spec.rb`:

```ruby
it "routes the description DSL to MCP transport, not axn's own internal Naming#description" do
  tool = Class.new(Axn::MCP::Tool) do
    description "A test tool"
    def call = nil
  end

  expect(tool.description_value).to eq("A test tool")
  expect(tool.to_h[:description]).to eq("A test tool")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/axn/mcp/tool_spec.rb -e "routes the description DSL"`
Expected: FAIL — `tool.description_value` returns `nil` instead of `"A test tool"`.

- [ ] **Step 3: Write minimal implementation**

Add to `Axn::MCP::Tool`'s `class << self` block in `lib/axn/mcp/tool.rb`, alongside the existing
`input_schema`/`output_schema` overrides (same file, same pattern — bind directly to `::MCP::Tool`'s
own method to skip over the extended `Axn::Core::Naming::ClassMethods#description` that `include
Axn` now puts ahead of it in the singleton ancestor chain):

```ruby
# axn core's Naming module (`include Axn`) also defines a class-level `description`, storing into
# its own `_axn_description` -- unrelated to MCP transport, but it sits ahead of ::MCP::Tool's own
# accessor in the singleton ancestor chain and silently shadows it. Bind directly to ::MCP::Tool's
# own method (same technique as input_schema/output_schema above) so `description "..."` keeps
# reaching @description_value, which `to_h` actually serializes to the MCP client.
def description(value = NOT_SET)
  method = ::MCP::Tool.singleton_class.instance_method(:description).bind(self)
  value == NOT_SET ? method.call : method.call(value)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/axn/mcp/tool_spec.rb spec/integration/server_integration_spec.rb`
Expected: PASS — all examples, including the two/three that were failing before this task.
Then run the full suite: `bundle exec rspec` — expect 0 failures gem-wide (this closes out the
pre-existing regression, so this is the first point since the `axn` bump where the full suite is
clean). Then `bundle exec rubocop` on `lib/axn/mcp/tool.rb` — 0 offenses.

- [ ] **Step 5: Commit**

```bash
git add lib/axn/mcp/tool.rb spec/axn/mcp/tool_spec.rb
git commit -m "PRO-2844: Fix description class-method collision from axn core's Naming module"
```

---

### Task 5: Route `server_context` through `ambient_context`; drop the hardcoded exclusion list

**Files:**
- Modify: `lib/axn/mcp/tool.rb`
- Modify: `spec/axn/mcp/tool_spec.rb`, `spec/integration/direct_axn_invocation_spec.rb`,
  `spec/integration/server_integration_spec.rb` (only if any assert on `server_context` being a
  *top-level* `expects` field rather than an ambient subfield — the public `server_context` reader
  behavior itself must NOT change).

**Interfaces:**
- Produces: `Axn::MCP::Tool` instances still expose a `server_context` reader with identical
  semantics (the raw injected value, `nil` when absent, never in `input_schema`) — but backed by
  `expects :server_context, on: :ambient_context` instead of a top-level field.
- Consumes: `Axn::MCP::Invocation.perform` (built in Task 6) — this task can stub it minimally first
  or, to keep task ordering TDD-clean, do Task 6's `Invocation` extraction *inside* this task, since
  the two are tightly coupled (moving `server_context` off the top level requires rewriting how
  `Tool.call` passes it into `ambient_context:`). Do Task 5 and Task 6 together as one commit if
  splitting them proves awkward in practice — flag this in the PR description rather than forcing an
  artificial seam.

- [ ] **Step 1: Write the failing test**

Add to `spec/axn/mcp/tool_spec.rb`, inside "server_context access":

```ruby
it "is excluded from input_schema via the ambient_context mechanism, not a hardcoded list" do
  tool = Class.new(Axn::MCP::Tool) do
    expects :name, type: String
    def call = nil
  end

  # No :server_context key anywhere in internal_field_configs — it's not a top-level field at all.
  expect(tool.internal_field_configs.map(&:field)).not_to include(:server_context)
  expect(tool.input_schema_value.to_h[:properties]).not_to have_key(:server_context)
end

it "does not leak Rails Current state into ambient_context when called via MCP" do
  current_class = Class.new(ActiveSupport::CurrentAttributes) { attribute :leaky }
  current_class.leaky = "should never appear"

  tool = Class.new(Axn::MCP::Tool) do
    expects :leaky, on: :ambient_context, optional: true
    def call
      expose result: leaky
    end
  end
  tool.exposes :result, type: String, optional: true

  response = tool.call(server_context: { user_id: 1 })
  expect(JSON.parse(response.content.first[:text])["result"]).to be_nil
ensure
  current_class&.reset
end
```

(This requires `require "active_support/current_attributes"` in `spec/spec_helper.rb` if not
already loaded — check first; `active_support/core_ext/object/blank` is already required elsewhere
in this gem so ActiveSupport itself is already a dependency.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/axn/mcp/tool_spec.rb -e "ambient_context"`
Expected: FAIL — `server_context` is still a top-level `expects` field, so it shows up in
`internal_field_configs`/`input_schema`, and there's no ambient-context routing yet to prevent
`Current` leakage (today's code never even reads `Axn.config.ambient_context_provider`, so this
second example may already accidentally pass or may error depending on `Current` wiring in this
gem's spec suite — treat either outcome as confirming the *current* code has no ambient-context
story, then proceed).

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/axn/mcp/tool.rb
module Axn
  module MCP
    class Tool < ::MCP::Tool
      include Axn
      include Axn::MCP.overrides

      expects :server_context, on: :ambient_context, optional: true,
              description: "MCP server context (injected automatically)"

      error { Axn::MCP.config.error_headline }

      class << self
        NOT_SET = Object.new.freeze

        def input_schema(value = NOT_SET)
          if value != NOT_SET
            super
          elsif @input_schema_value
            @input_schema_value
          else
            @input_schema_value = ::MCP::Tool::InputSchema.new(
              Axn::Reflection::Schema.build_input(internal_field_configs, subfield_configs),
            )
          end
        end

        def input_schema_value
          @input_schema_value || input_schema
        end

        def output_schema(value = NOT_SET)
          if value != NOT_SET
            super
          elsif @output_schema_value
            @output_schema_value
          elsif external_field_configs.empty?
            nil
          else
            @output_schema_value = ::MCP::Tool::OutputSchema.new(
              Axn::Reflection::Schema.build_output(external_field_configs),
            )
          end
        end

        def output_schema_value
          return @output_schema_value if @output_schema_value
          return nil if external_field_configs.empty?

          output_schema
        end

        def to_h
          input_schema
          output_schema unless external_field_configs.empty?
          super
        end

        def call(**kwargs)
          return Invocation.perform(self, kwargs, text_content: resolved_mcp_text_content) if kwargs.key?(:server_context)

          new(**kwargs).tap(&:_run).result
        end

        def call!(**)
          result = call(**)
          return result if result.is_a?(::MCP::Tool::Response)
          return result if result.ok?

          raise result.exception
        end

        # ... read_only!/destructive!/idempotent!/open_world!/closed_world!/define unchanged (Task 6+ touches these)
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/axn/mcp/tool_spec.rb spec/integration/server_integration_spec.rb spec/integration/direct_axn_invocation_spec.rb`
Expected: PASS — this depends on `Axn::MCP::Invocation` existing, so implement Task 6's
`invocation.rb` alongside this step (see note in Interfaces above about merging Tasks 5/6).

- [ ] **Step 5: Commit**

```bash
git add lib/axn/mcp/tool.rb lib/axn/mcp/invocation.rb lib/axn/mcp.rb spec/axn/mcp/tool_spec.rb
git commit -m "PRO-2844: Route server_context through ambient_context, not a top-level field"
```

---

### Task 6: Extract shared invocation logic (`Axn::MCP::Invocation`)

**Files:**
- Create: `lib/axn/mcp/invocation.rb`
- Modify: `lib/axn/mcp.rb` (require it)
- Test: covered by Task 5's and Task 7's specs (this task has no new user-facing behavior of its
  own — it's a pure extraction so `Tool.call` and `Axn::MCP.wrap` share one code path).

**Interfaces:**
- Produces: `Axn::MCP::Invocation.perform(axn_class, kwargs, text_content:) -> MCP::Tool::Response`.
  Extracts `server_context:` out of `kwargs` (defaults to `nil` if absent — callers only invoke this
  when they know an MCP call is happening), calls
  `axn_class.call(ambient_context: { server_context: }, **kwargs.except(:server_context))`, and maps
  the result via `Axn::MCP::Serializer.result_to_mcp_response`.

- [ ] **Step 1: Write the failing test**

This is exercised indirectly by Task 5's and Task 7's specs (both call through `Tool.call` /
`Axn::MCP.wrap`-generated `.call`). Add one direct unit test for isolation:

```ruby
# spec/axn/mcp/invocation_spec.rb
# frozen_string_literal: true

RSpec.describe Axn::MCP::Invocation do
  describe ".perform" do
    it "maps server_context into ambient_context, not a top-level kwarg" do
      axn_class = Class.new do
        include Axn
        expects :name, type: String
        expects :server_context, on: :ambient_context, optional: true
        exposes :seen_context, type: Hash, optional: true

        def call
          expose seen_context: server_context
        end
      end

      response = described_class.perform(axn_class, { name: "Alice", server_context: { user_id: 1 } }, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen_context"]).to eq("user_id" => 1)
    end

    it "passes ambient_context: nil explicitly (not omitted) when server_context is nil, so no Current default leaks in" do
      axn_class = Class.new do
        include Axn
        expects :leaky, on: :ambient_context, optional: true
        exposes :result, type: String, optional: true
        def call = expose(result: leaky)
      end

      response = described_class.perform(axn_class, {}, text_content: :structured)
      expect(JSON.parse(response.content.first[:text])["result"]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/axn/mcp/invocation_spec.rb`
Expected: FAIL — `uninitialized constant Axn::MCP::Invocation`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/axn/mcp/invocation.rb
# frozen_string_literal: true

module Axn
  module MCP
    # Shared "server_context: -> ambient_context: -> call -> MCP::Tool::Response" path used by both
    # Axn::MCP::Tool#call (the with-server_context branch, back-compat dual-mode) and
    # Axn::MCP.wrap-generated classes (PRO-2844). An explicit ambient_context: kwarg replaces axn
    # core's default Current-attributes-derived ambient_context (see Axn::Core::AmbientContext) --
    # passing it here even when server_context is nil is what stops server-side Current leaking in.
    module Invocation
      module_function

      def perform(axn_class, kwargs, text_content:)
        server_context = kwargs[:server_context]
        rest = kwargs.reject { |k, _| k == :server_context }

        result = axn_class.call(ambient_context: { server_context: server_context }, **rest)
        Serializer.result_to_mcp_response(result, axn_class.external_field_configs, text_content:)
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/axn/mcp/invocation_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/axn/mcp/invocation.rb lib/axn/mcp.rb spec/axn/mcp/invocation_spec.rb
git commit -m "PRO-2844: Extract Axn::MCP::Invocation as the shared server_context->ambient_context path"
```

---

### Task 7: `Axn::MCP.wrap` — expose a plain Axn as an `::MCP::Tool`

**Files:**
- Create: `lib/axn/mcp/wrap.rb`
- Modify: `lib/axn/mcp.rb` (require it)
- Test: `spec/axn/mcp/wrap_spec.rb`

**Interfaces:**
- Consumes: `Axn::MCP::Invocation.perform` (Task 6), `Axn::Reflection::Schema.build_input`/
  `.build_output` (Task 3), `Axn::MCP::Annotations.annotations_for` (Task 1).
- Produces: `Axn::MCP.wrap(axn_class, description:, name: nil, annotations: nil, mcp_text_content: Axn::MCP.config.mcp_text_content) -> Class` — a fresh `::MCP::Tool` subclass. Calling the
  wrapped class's OWN `.call`/`.call!` directly (unwrapped) still returns plain `Axn::Result` — wrap
  never touches the original class.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/axn/mcp/wrap_spec.rb
# frozen_string_literal: true

RSpec.describe "Axn::MCP.wrap" do
  let(:plain_axn) do
    Class.new do
      include Axn
      def self.name = "GreetPlainly"

      expects :name, type: String
      expects :user_id, on: :ambient_context, optional: true
      exposes :greeting, type: String

      def call
        expose greeting: "Hello, #{name}! (user #{user_id.inspect})"
      end
    end
  end

  it "proves author-once: the original Axn is untouched and still returns Axn::Result directly" do
    result = plain_axn.call(name: "Alice")

    expect(result).to be_a(Axn::Result)
    expect(result).to be_ok
    expect(result.greeting).to eq("Hello, Alice! (user nil)")
  end

  it "wraps a plain Axn as an ::MCP::Tool subclass" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

    expect(tool).to be < ::MCP::Tool
    expect(tool.description).to eq("Greets someone")
    expect(tool.input_schema_value.to_h[:properties]).to have_key(:name)
    expect(tool.input_schema_value.to_h[:properties]).not_to have_key(:user_id)
  end

  it "maps server_context into the wrapped Axn's ambient_context" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

    response = tool.call(name: "Bob", server_context: { user_id: 42 })

    expect(response).to be_a(::MCP::Tool::Response)
    expect(JSON.parse(response.content.first[:text])["greeting"]).to eq("Hello, Bob! (user 42)")
  end

  it "sets annotations from the wrap kwarg" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone", annotations: { read_only_hint: true })

    expect(tool.annotations_value.read_only_hint).to be true
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/axn/mcp/wrap_spec.rb`
Expected: FAIL — `undefined method 'wrap' for Axn::MCP`

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/axn/mcp/wrap.rb
# frozen_string_literal: true

module Axn
  module MCP
    class << self
      # Exposes any Axn (whether or not it subclasses Axn::MCP::Tool) as an ::MCP::Tool subclass.
      # The wrapped class's own .call/.call! are untouched -- direct callers keep getting a plain
      # Axn::Result. All MCP transport concerns (schema, server_context routing, response mapping)
      # live entirely on the generated subclass, via the same Axn::MCP::Invocation path
      # Axn::MCP::Tool#call uses -- proves the "author once" story from PRO-2844/PRO-2842.
      def wrap(axn_class, description:, name: nil, annotations: nil, mcp_text_content: Axn::MCP.config.mcp_text_content)
        Class.new(::MCP::Tool) do
          tool_name(name) if name
          description(description)

          input_schema(Axn::Reflection::Schema.build_input(axn_class.internal_field_configs, axn_class.subfield_configs))
          unless axn_class.external_field_configs.empty?
            output_schema(Axn::Reflection::Schema.build_output(axn_class.external_field_configs))
          end

          hint_annotations = Axn::MCP::Annotations.annotations_for(axn_class._semantic_hints)
          self.annotations(**(annotations || hint_annotations)) if annotations || hint_annotations.any?

          define_singleton_method(:call) do |**kwargs|
            Axn::MCP::Invocation.perform(axn_class, kwargs, text_content: mcp_text_content)
          end

          define_singleton_method(:call!) do |**kwargs|
            result = call(**kwargs)
            result
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/axn/mcp/wrap_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/axn/mcp/wrap.rb lib/axn/mcp.rb spec/axn/mcp/wrap_spec.rb
git commit -m "PRO-2844: Add Axn::MCP.wrap to expose a plain Axn as an ::MCP::Tool"
```

---

### Task 8: Map declared `semantic_hints` to MCP annotations as a default; add `open_world`/`closed_world`

**Files:**
- Modify: `lib/axn/mcp/tool.rb`
- Modify: `spec/axn/mcp/tool_spec.rb`

**Interfaces:**
- Produces: `Tool.semantic_hints(:read_only)` (core's generic DSL) sets
  `annotations_value.read_only_hint == true` **only if** `annotations(...)` was never called
  explicitly on that class (explicit always wins). `Tool.open_world`/`Tool.closed_world` (new,
  additive) call `semantic_hints` with the MCP-only hint and immediately apply the derived
  annotation. `read_only!`/`destructive!`/`idempotent!`/`open_world!`/`closed_world!` (existing bang
  methods) are UNCHANGED byte-for-byte — still call `annotations(...)` directly with their current
  hardcoded hashes; do not route them through `semantic_hints` (see Global Constraints: their
  full-replace quirks are pinned by existing specs).

- [ ] **Step 1: Write the failing test**

```ruby
# spec/axn/mcp/tool_spec.rb — new describe block near the existing annotations specs
describe "semantic_hints -> MCP annotations default mapping" do
  it "derives read_only_hint from a declared semantic_hints :read_only" do
    tool = Class.new(Axn::MCP::Tool) do
      semantic_hints :read_only
      def call = nil
    end

    expect(tool.annotations_value.read_only_hint).to be true
  end

  it "does not override an explicitly-declared annotations(...) call" do
    tool = Class.new(Axn::MCP::Tool) do
      semantic_hints :read_only
      annotations(title: "Explicit Title")
      def call = nil
    end

    expect(tool.annotations_value.read_only_hint).to be false # explicit annotations() call wins, reverts to MCP default
    expect(tool.annotations_value.title).to eq("Explicit Title")
  end

  it "supports open_world as a semantic hint, registered via the extension registry (no core change)" do
    tool = Class.new(Axn::MCP::Tool) do
      open_world
      def call = nil
    end

    expect(tool.semantic_hints).to include(:open_world)
    expect(tool.annotations_value.open_world_hint).to be true
  end

  it "supports closed_world as a semantic hint" do
    tool = Class.new(Axn::MCP::Tool) do
      closed_world
      def call = nil
    end

    expect(tool.semantic_hints).to include(:closed_world)
    expect(tool.annotations_value.open_world_hint).to be false
  end

  it "keeps the legacy read_only! bang method's exact prior behavior" do
    tool = Class.new(Axn::MCP::Tool) do
      read_only!
      def call = nil
    end

    expect(tool.annotations_value.read_only_hint).to be true
    expect(tool.annotations_value.destructive_hint).to be false
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/axn/mcp/tool_spec.rb -e "semantic_hints -> MCP annotations"`
Expected: FAIL — `open_world`/`closed_world` (non-bang) undefined; `annotations_value` never
reflects `semantic_hints` today.

- [ ] **Step 3: Write minimal implementation**

Add to `Axn::MCP::Tool`'s `class << self` block (`lib/axn/mcp/tool.rb`):

```ruby
def semantic_hints(*hints)
  return super if hints.empty?

  super
  annotations(**Axn::MCP::Annotations.annotations_for(_semantic_hints)) if annotations_value.nil?
end

def open_world
  semantic_hints(*(_semantic_hints + [:open_world] - [:closed_world]))
end

def closed_world
  semantic_hints(*(_semantic_hints + [:closed_world] - [:open_world]))
end
```

`annotations_value.nil?` is the "was `annotations(...)` ever called explicitly" check — `::MCP::Tool`
never sets `@annotations_value` until `annotations(hash)` is called, so this correctly detects
"nothing explicit yet" without adding new state. Because `semantic_hints` re-derives from the FULL
`_semantic_hints` list every time (not an incremental patch), calling `open_world` then `closed_world`
on the same class correctly ends with only `closed_world`'s annotation applied — no stacking bugs.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/axn/mcp/tool_spec.rb`
Expected: PASS, full file (all existing + new examples).

- [ ] **Step 5: Commit**

```bash
git add lib/axn/mcp/tool.rb spec/axn/mcp/tool_spec.rb
git commit -m "PRO-2844: Default MCP annotations from declared semantic_hints; add open_world/closed_world"
```

---

### Task 9: Full regression pass, CHANGELOG, version bump, README

**Files:**
- Modify: `CHANGELOG.md`, `lib/axn/mcp/version.rb`, `README.md`

**Interfaces:** none (documentation/metadata only).

- [ ] **Step 1: Run the full suite and rubocop**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: PASS, 0 offenses. Fix anything Tasks 1–8 missed (in particular re-check
`spec/integration/server_integration_spec.rb` and `spec/axn/mcp/config_spec.rb` for any leftover
assumption about `server_context` being a top-level field).

- [ ] **Step 2: Grep for dead references**

Run: `grep -rn "SchemaBuilder\|EXCLUDED_FROM_SCHEMA" lib spec README.md`
Expected: no matches.

- [ ] **Step 3: Update `CHANGELOG.md`**

Add an entry above `## 0.1.1`:

```markdown
## 0.2.0

- Adopted `axn` core's JSON Schema reflection (`Axn::Reflection::Schema`) and exposed-value
  serialization (`Axn::Reflection::Values`), added in axn PRO-2842. `Axn::MCP::SchemaBuilder` and
  `Axn::MCP::Serializer.serialize_exposed`/`.serialize_value` are removed — schema/serialization
  logic now lives in axn core, and is a strict superset of the old behavior (nullable fields now
  reflect as `type: [X, "null"]`; boolean fields gain an explicit `enum: [true]`/`[false]`).
- `server_context` is no longer a declared top-level field on `Axn::MCP::Tool` — it's routed through
  axn core's new `ambient_context` mechanism (`expects :server_context, on: :ambient_context`). The
  public `server_context` reader inside a tool's `#call` is unchanged (still the raw injected value,
  `nil` when absent, never present in `inputSchema`); this also means an explicit `server_context:`
  now fully replaces any process-wide `Current`-attributes-derived ambient context for that call,
  so no server-side state can leak into an MCP invocation.
- Added `Axn::MCP.wrap(any_axn, description:, **opts)`, exposing a plain Axn (one that does not
  subclass `Axn::MCP::Tool`) as an `::MCP::Tool` subclass — "author once," per axn PRO-2842/PRO-2844.
- Added `open_world`/`closed_world` as `semantic_hints`, registered via
  `Axn.extension_config.register_semantic_hint` (axn core's new extension registry) — no core change
  needed to add MCP-spec-only vocabulary. A class's declared `semantic_hints` now drive its MCP
  annotations by default (`:read_only`/`:idempotent`/`:destructive`/`:open_world`/`:closed_world` →
  the matching `*_hint`), unless the class calls `annotations(...)` explicitly, which always wins.
  `read_only!`/`destructive!`/`idempotent!`/`open_world!`/`closed_world!` remain as unchanged,
  independent convenience methods.
- Requires an `axn` version that ships `Axn::Core::SchemaReflection`, `Axn::Core::SemanticHints`,
  `Axn::Core::AmbientContext`, `Axn::ExtensionConfig#register_semantic_hint`, and
  `Axn::Reflection::{Schema,Values}` (axn PRO-2842).
```

- [ ] **Step 4: Bump version**

```ruby
# lib/axn/mcp/version.rb
module Axn
  module MCP
    VERSION = "0.2.0"
  end
end
```

- [ ] **Step 5: Update README.md**

Find and rewrite the sections describing: (a) automatic JSON Schema generation (mention it's now
sourced from axn core's reflection), (b) `server_context` (mention `ambient_context` routing, keep
the "excluded from inputSchema" and "nil when called directly" guarantees as still-true), (c) add a
new section documenting `Axn::MCP.wrap` alongside the existing `Axn::MCP::Tool` subclassing section,
with a short example mirroring `spec/axn/mcp/wrap_spec.rb`'s "wraps a plain Axn" scenario, (d)
document `open_world`/`closed_world` and the semantic_hints-to-annotations default mapping next to
the existing `read_only!` etc. annotations section.

- [ ] **Step 6: Final full-suite run**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: PASS, 0 offenses.

- [ ] **Step 7: Commit**

```bash
git add CHANGELOG.md lib/axn/mcp/version.rb README.md
git commit -m "PRO-2844: Release 0.2.0 — core reflection, ambient_context, Axn::MCP.wrap"
```

---

## Self-Review Notes (for the plan author — already applied above)

- **Spec coverage:** ticket scope items 1 (delete SchemaBuilder/Serializer methods, drop exclusion
  list) → Tasks 2–3, 5; item 2 (extension registry for `open_world`/`closed_world`/`text_content`,
  semantic_hints → annotations mapping, bang-method fate) → Tasks 1, 8 (text_content: covered by
  Global Constraints note — already satisfied by the existing `Axn::Configurable`-backed
  `mcp_text_content` override, no task needed); item 3 (`Axn::MCP.wrap`) → Task 7; item 4 (context
  injection via `ambient_context`) → Tasks 5–6; item 5 (back-compat `Axn::MCP::Tool`, `define`
  factory unchanged) → Task 5 (kept dual-mode `.call`), `define` explicitly untouched throughout.
  Acceptance criterion "7 os-app tools produce identical schemas/responses" is not independently
  verifiable from this repo (os-app isn't checked out here) — Task 9's full regression pass against
  this gem's own spec suite (which encodes the same `Axn::MCP::Tool` subclassing pattern os-app
  uses) is the available proxy; call this out explicitly when handing off for os-app-side follow-up
  verification.
- **Placeholder scan:** no TBD/"add error handling"/"similar to Task N" — every step shows full
  code or an exact command with a stated expected result.
- **Type consistency:** `Axn::MCP::Invocation.perform(axn_class, kwargs, text_content:)` signature
  matches between Task 6 (definition), Task 5 (`Tool.call`'s use), and Task 7 (`wrap`'s use).
  `Axn::MCP::Annotations.annotations_for(hints)` signature matches between Task 1 (definition),
  Task 7 (`wrap`'s use), and Task 8 (`Tool.semantic_hints`'s use).
