# frozen_string_literal: true

module Axn
  module MCP
    class Tool < ::MCP::Tool
      include Axn
      include Axn::MCP.overrides

      # type: Object (not Hash): the `mcp` gem doesn't guarantee a raw Hash here across its own
      # version range -- newer versions (e.g. 0.23) wrap it in an MCP::ServerContext object (which
      # delegates arbitrary methods like #dig to the underlying context via method_missing), while
      # direct/test calls typically pass a plain Hash. `type: Object` (true for any value via
      # `is_a?`) just satisfies axn core's "at least one validation" requirement for an ambient
      # subfield without constraining to a shape the transport doesn't actually guarantee.
      expects :server_context, on: :ambient_context, type: Object, optional: true,
                               description: "MCP server context (injected automatically)"

      # The raw hash from THIS class's (or an ancestor's, since class_attribute inherits) most
      # recent explicit `annotations(...)` call, or nil if none. A class_attribute, not a plain
      # ivar or boolean flag, for two reasons: (1) visibility to subclasses -- a subclass otherwise
      # starts with its own nil `@annotations_value` (mcp's own `inherited` hook resets it) and no
      # memory of an ancestor's explicit call; (2) the VALUE itself must inherit, not just a
      # "was explicit" flag -- an earlier version tracked only a boolean here, which correctly told
      # a subclass "don't derive from semantic_hints", but then fell through to `super`
      # (`@annotations_value`), which is nil on the subclass itself, silently losing the base
      # class's actual explicit annotations instead of inheriting them.
      class_attribute :_mcp_explicit_annotations_hash, instance_accessor: false, default: nil

      # Base error headline, read fresh from config on every failure (a block, not a literal, so
      # Axn::MCP.config.error_headline= takes effect immediately -- no reload/require-order gotcha).
      # Two coupled effects (see axn's Axn::Configurable error prefixing):
      #   1. Replaces axn's generic "Something went wrong" for failures with no explicit reason
      #      (validation errors, unexpected exceptions, bare `fail!`) -> the configured headline.
      #   2. Prefixes explicit `fail!("reason")` messages as "<headline>: reason".
      # Gem-wide default: Axn::MCP.config.error_headline = "...". Per-tool: declare a subclass's
      # own base `error "..."`, or opt a single message out with `fail!("...", standalone: true)`.
      error { Axn::MCP.config.error_headline }

      class << self
        NOT_SET = Object.new.freeze

        def input_schema(value = NOT_SET)
          if value != NOT_SET
            # Plain `super` (not a bind-trick): axn core's Axn::Core::MethodShadowing (axn PRO-2875)
            # now defers to a pre-existing same-named method on a non-axn-core ancestor, so
            # Axn::Core::SchemaReflection::ClassMethods#input_schema is never extended onto this
            # class at all -- ::MCP::Tool's own setter is the only one in the ancestor chain.
            super
          elsif @input_schema_value
            @input_schema_value
          else
            # server_context is declared `on: :ambient_context` (see above), so axn core's own
            # Axn::Reflection::Schema.build_input already excludes it (and any other ambient
            # subfield) from internal_field_configs/properties -- no hand-rolled exclusion list needed.
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
            # See input_schema's comment: plain `super` is safe here too, same reason.
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

        # No override needed here anymore: axn core's Naming module (`include Axn`) used to define
        # its own class-level `description` (storing into `_axn_description`, unrelated to MCP
        # transport) that shadowed ::MCP::Tool's own accessor -- fixed upstream by axn's
        # Axn::Core::MethodShadowing (PRO-2875), which now defers to ::MCP::Tool's pre-existing
        # `description` instead of extending its own. Plain inheritance handles it.

        def to_h
          input_schema
          output_schema unless external_field_configs.empty?
          super
        end

        def call(**kwargs)
          # Branch on presence of server_context: (back-compat contract, must not change):
          # - Present: called from MCP server -- route server_context into ambient_context: via the
          #   shared Invocation helper, return MCP::Tool::Response
          # - Absent: called directly as Axn, return Axn::Result
          # Check both the Symbol and String forms of the key: a forwarding layer that splats
          # parsed JSON without symbolizing first (the same case Invocation.perform itself
          # defends against) would otherwise fall through to direct-Axn mode and return the wrong
          # response type even though the caller clearly intended an MCP-mode call.
          return Invocation.perform(self, kwargs, text_content: resolved_mcp_text_content) if kwargs.key?(:server_context) || kwargs.key?("server_context")

          # Direct-Axn mode still needs the same "no Current leakage" guarantee Invocation.perform
          # gives the MCP-mode branch above: server_context is declared on: :ambient_context, so
          # without an explicit ambient_context: here axn core would fall back to its configured
          # Current-attributes-derived default, letting a stale server_context leak in even though
          # this call never received one -- violating the documented "nil when called directly"
          # contract. Only inject the empty default when the caller hasn't already supplied their
          # own explicit ambient_context: (their call, their responsibility, same as any other Axn).
          kwargs = { ambient_context: {} }.merge(kwargs) unless kwargs.key?(:ambient_context)
          new(**kwargs).tap(&:_run).result
        end

        def call!(**)
          result = call(**)

          # For MCP calls (with server_context), just return the response
          return result if result.is_a?(::MCP::Tool::Response)

          # For direct Axn calls, raise on failure
          return result if result.ok?

          raise result.exception
        end

        # Deprecated convenience DSL for annotations, kept only for back-compat -- prefer
        # `semantic_hints`/`open_world`/`closed_world` below. These used to call `annotations(...)`
        # directly, independent of `semantic_hints` entirely, which meant `.semantic_hints` never
        # reflected a bang-method call. Now thin aliases over `semantic_hints`, so both stay
        # coherent; mutually exclusive where the old full-replace `annotations()` calls implied it
        # (read_only!/destructive!, open_world!/closed_world!), additive where it didn't
        # (idempotent!, same as before). Because these now route through `semantic_hints`, an
        # explicit `annotations(...)` call still wins over them too, same as the non-bang methods.
        def read_only!
          Axn::MCP.deprecator.warn("`read_only!` is deprecated and will be removed in a future release. Use `semantic_hints :read_only` instead.")
          semantic_hints(*(_semantic_hints + [:read_only] - [:destructive]))
        end

        def destructive!
          Axn::MCP.deprecator.warn("`destructive!` is deprecated and will be removed in a future release. Use `semantic_hints :destructive` instead.")
          semantic_hints(*(_semantic_hints + [:destructive] - [:read_only]))
        end

        def idempotent!
          Axn::MCP.deprecator.warn("`idempotent!` is deprecated and will be removed in a future release. Use `semantic_hints :idempotent` instead.")
          semantic_hints(*(_semantic_hints | [:idempotent]))
        end

        def open_world!
          Axn::MCP.deprecator.warn("`open_world!` is deprecated and will be removed in a future release. Use `open_world` instead.")
          semantic_hints(*(_semantic_hints + [:open_world] - [:closed_world]))
        end

        def closed_world!
          Axn::MCP.deprecator.warn("`closed_world!` is deprecated and will be removed in a future release. Use `closed_world` instead.")
          semantic_hints(*(_semantic_hints + [:closed_world] - [:open_world]))
        end

        # Tracks whether `annotations(...)` was ever called explicitly (see the class_attribute
        # declared above the `class << self` block) -- explicit always wins over the semantic_hints
        # default below, and this deliberately does NOT get set by that default's own derivation
        # (see `annotations_value` below, which sets @annotations_value directly rather than
        # calling back through this method).
        #
        # The getter path (no args) delegates to `annotations_value` below rather than `super`:
        # `MCP::Server`'s own protocol-version validation reads `tool.annotations` (this method),
        # while serialization reads `tool.annotations_value` -- if only the latter derived from
        # semantic_hints, a hint-derived annotation could be emitted without ever passing that
        # validation. The setter path can't use plain `super`/`super()` either -- unlike
        # input_schema/output_schema above (whose shadowing is now fixed upstream by axn's
        # Axn::Core::MethodShadowing, PRO-2875), this one is unrelated to that: axn core has never
        # defined an `annotations` method at all. This is purely a `NOT_SET` sentinel mismatch --
        # our own `NOT_SET` (defined above, in this class's `class << self`) is a different object
        # from `::MCP::Tool`'s own internal `NOT_SET`, so forwarding it as `hash` would make
        # `::MCP::Tool` wrongly treat "no argument given" as "given this literal Object" and crash
        # trying to build `Annotations.new(**that_object)`. Bind directly to `::MCP::Tool`'s own
        # setter instead to sidestep the sentinel mismatch.
        def annotations(hash = NOT_SET)
          return annotations_value if hash == NOT_SET

          self._mcp_explicit_annotations_hash = hash
          ::MCP::Tool.singleton_class.instance_method(:annotations).bind(self).call(hash)
        end

        # Default MCP annotations from axn core's generic `semantic_hints` DSL -- but only when
        # `annotations(...)` was never called explicitly (on this class OR an ancestor; see
        # `_mcp_explicit_annotations_hash` above). Rebuilds from the stored hash (rather than
        # falling through to `super`/`@annotations_value`) so an ancestor's explicit call is
        # visible on a subclass that never overrides it -- `@annotations_value` itself is NOT
        # inherited (`::MCP::Tool`'s own `inherited` hook resets it to nil for every subclass), but
        # `_mcp_explicit_annotations_hash` (a class_attribute) is, so this stays correct at any
        # depth. Derives semantic-hints defaults lazily, on every read, from the FULL current
        # `_semantic_hints` list (not an incremental patch) -- rather than eagerly inside
        # `semantic_hints`/`open_world`/`closed_world` -- so it's idempotent under repeated/
        # overlapping hint declarations (e.g. open_world then closed_world nets only closed_world's
        # annotation), AND so a subclass that inherits `_semantic_hints` from a base class without
        # redeclaring them still gets the right annotations.
        def annotations_value
          return ::MCP::Tool::Annotations.new(**_mcp_explicit_annotations_hash) if _mcp_explicit_annotations_hash

          mapped = Axn::MCP::Annotations.annotations_for(_semantic_hints)
          # Empty either because no hints are declared, or because every declared hint (e.g. one a
          # different adapter registered and uses, like :cacheable) maps to no MCP annotation at
          # all -- either way, that's "nothing to derive", not "apply every Annotations.new default"
          # (destructive_hint: true, open_world_hint: true, etc.), which would misrepresent a tool
          # that never asked for those defaults and could fail an MCP::Server protocol-version check.
          return super if mapped.empty?

          ::MCP::Tool::Annotations.new(**mapped)
        end

        # Non-bang counterparts to open_world!/closed_world! (which remain unchanged above): these
        # just update `_semantic_hints` via axn core's own DSL -- `annotations_value` above derives
        # the MCP annotation from it lazily, so an explicit `annotations(...)` call still wins.
        def open_world
          semantic_hints(*(_semantic_hints + [:open_world] - [:closed_world]))
        end

        def closed_world
          semantic_hints(*(_semantic_hints + [:closed_world] - [:open_world]))
        end

        # Factory-style tool definition for quick one-off tools
        def define(description:, expects: [], exposes: [], annotations: nil, mcp_text_content: NOT_SET, **_opts, &block)
          tool_class = Class.new(self) do
            include Axn unless self < Axn
          end

          FieldDeclarations.hydrate(expects).each do |field, field_opts|
            tool_class.expects(field, **field_opts)
          end

          FieldDeclarations.hydrate(exposes).each do |field, field_opts|
            tool_class.exposes(field, **field_opts)
          end

          tool_class.description(description)
          tool_class.annotations(annotations) if annotations
          tool_class.mcp_text_content(mcp_text_content) if mcp_text_content != NOT_SET

          tool_class.define_method(:call, &block) if block

          tool_class
        end
      end
    end
  end
end
