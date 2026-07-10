# frozen_string_literal: true

module Axn
  module MCP
    class Tool < ::MCP::Tool
      include Axn
      include Axn::MCP.overrides

      expects :server_context, optional: true, description: "MCP server context (injected automatically)"

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

        # server_context is an axn-mcp convention (injected by the MCP server, never supplied by the
        # client) -- not an axn-core concept, so core's Axn::Reflection::Schema (which only excludes
        # its own :ambient_context) doesn't know to hide it. Filter it out here before reflecting.
        EXCLUDED_FROM_INPUT_SCHEMA = %i[server_context].freeze

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
            schema_field_configs = internal_field_configs.reject { |c| EXCLUDED_FROM_INPUT_SCHEMA.include?(c.field) }
            @input_schema_value = ::MCP::Tool::InputSchema.new(
              Axn::Reflection::Schema.build_input(schema_field_configs, subfield_configs),
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

        def to_h
          input_schema
          output_schema unless external_field_configs.empty?
          super
        end

        def call(**kwargs)
          result = new(**kwargs).tap(&:_run).result

          # Branch on presence of server_context:
          # - Present: called from MCP server, return MCP::Tool::Response
          # - Absent: called directly as Axn, return Axn::Result
          return result unless kwargs.key?(:server_context)

          Serializer.result_to_mcp_response(result, external_field_configs, text_content: resolved_mcp_text_content)
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
