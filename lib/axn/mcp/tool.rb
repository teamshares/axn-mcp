# frozen_string_literal: true

module Axn
  module MCP
    class Tool < ::MCP::Tool
      include Axn

      expects :server_context, type: Hash, optional: true, description: "MCP server context (injected automatically)"

      class << self
        NOT_SET = Object.new.freeze

        def mcp_text_content(value = NOT_SET)
          if value == NOT_SET
            resolved_mcp_text_content
          else
            Config.validate_mcp_text_content!(value)
            @mcp_text_content = value
          end
        end

        def resolved_mcp_text_content
          if instance_variable_defined?(:@mcp_text_content) && !@mcp_text_content.nil?
            @mcp_text_content
          else
            Axn::MCP.config.mcp_text_content
          end
        end

        def input_schema(value = NOT_SET)
          if value != NOT_SET
            super
          elsif @input_schema_value
            @input_schema_value
          else
            @input_schema_value = ::MCP::Tool::InputSchema.new(
              SchemaBuilder.build_input(internal_field_configs, subfield_configs),
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
              SchemaBuilder.build_output(external_field_configs),
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
