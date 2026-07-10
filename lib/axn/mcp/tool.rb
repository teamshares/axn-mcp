# frozen_string_literal: true

module Axn
  module MCP
    class Tool < ::MCP::Tool
      include Axn
      include Axn::MCP.overrides

      expects :server_context, on: :ambient_context, type: Hash, optional: true,
                               description: "MCP server context (injected automatically)"

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
            # Explicit-arg super, not bare `super`/`super()`: `include Axn` puts axn core's own
            # Axn::Core::SchemaReflection::ClassMethods#input_schema (a ZERO-arg reflection reader,
            # unrelated to this manual-override path) ahead of ::MCP::Tool's in the singleton ancestor
            # chain, so a forwarding `super` would hit the wrong, arity-0 method. Bind directly to
            # ::MCP::Tool's own setter to skip over it.
            ::MCP::Tool.singleton_class.instance_method(:input_schema).bind(self).call(value)
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
            # See input_schema's comment: skip axn core's zero-arg SchemaReflection#output_schema.
            ::MCP::Tool.singleton_class.instance_method(:output_schema).bind(self).call(value)
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

        # axn core's Naming module (`include Axn`) also defines a class-level `description`, storing into
        # its own `_axn_description` -- unrelated to MCP transport, but it sits ahead of ::MCP::Tool's own
        # accessor in the singleton ancestor chain and silently shadows it. Bind directly to ::MCP::Tool's
        # own method (same technique as input_schema/output_schema above) so `description "..."` keeps
        # reaching @description_value, which `to_h` actually serializes to the MCP client.
        def description(value = NOT_SET)
          method = ::MCP::Tool.singleton_class.instance_method(:description).bind(self)
          value == NOT_SET ? method.call : method.call(value)
        end

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
          return Invocation.perform(self, kwargs, text_content: resolved_mcp_text_content) if kwargs.key?(:server_context)

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

        # Convenience DSL for annotations
        # See: https://github.com/modelcontextprotocol/ruby-sdk#tool-annotations
        #
        # Available annotations:
        #   destructive_hint: true/false - Indicates if tool performs destructive operations (default: true)
        #   idempotent_hint: true/false - Indicates if tool's operations are idempotent (default: false)
        #   open_world_hint: true/false - Indicates if tool operates in open world context (default: true)
        #   read_only_hint: true/false - Indicates if tool only reads data (default: false)
        #   title: "string" - Human-readable title for the tool

        def read_only!
          annotations(read_only_hint: true, destructive_hint: false)
        end

        def destructive!
          annotations(destructive_hint: true, read_only_hint: false)
        end

        def idempotent!
          annotations(idempotent_hint: true)
        end

        def open_world!
          annotations(open_world_hint: true)
        end

        def closed_world!
          annotations(open_world_hint: false)
        end

        # Tracks whether THIS class ever called `annotations(...)` explicitly, as distinct from our
        # own auto-derivation below (which sets @annotations_value directly, bypassing this method,
        # so it never marks itself as "explicit"). A plain `annotations_value.nil?` check isn't
        # enough: once the first `semantic_hints` call auto-derives annotations, @annotations_value
        # is no longer nil, so a naive nil-check would block every later hint change from
        # re-deriving -- this flag is what still distinguishes "we set it" from "the user set it".
        def annotations(hash = NOT_SET)
          @_mcp_explicit_annotations = true if hash != NOT_SET
          super
        end

        # Default MCP annotations from axn core's generic `semantic_hints` DSL -- but only when
        # this class never called `annotations(...)` explicitly (explicit always wins; see
        # `@_mcp_explicit_annotations` above).
        #
        # Re-derives from the FULL `_semantic_hints` list every call (not an incremental patch), so
        # this is idempotent under repeated/overlapping declarations (e.g. open_world then
        # closed_world ends with only closed_world's annotation applied) -- setting @annotations_value
        # directly here (not via `annotations(...)`) is what keeps `@_mcp_explicit_annotations` false
        # across our own repeated auto-derivations.
        def semantic_hints(*hints)
          return super if hints.empty?

          super
          return if @_mcp_explicit_annotations

          @annotations_value = ::MCP::Tool::Annotations.new(**Axn::MCP::Annotations.annotations_for(_semantic_hints))
        end

        # Non-bang counterparts to open_world!/closed_world! (which remain unchanged above): these
        # go through the semantic_hints-driven default mechanism rather than calling `annotations`
        # directly, so an explicit `annotations(...)` call still wins over them.
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
