# frozen_string_literal: true

module Axn
  module MCP
    class << self
      # Exposes any Axn (whether or not it subclasses Axn::MCP::Tool) as an ::MCP::Tool subclass.
      # The wrapped class's own .call/.call! are untouched -- direct callers keep getting a plain
      # Axn::Result. All MCP transport concerns (schema, server_context routing, response mapping)
      # live entirely on the generated subclass, via the same Axn::MCP::Invocation path
      # Axn::MCP::Tool#call uses -- proves the "author once" story from PRO-2844/PRO-2842.
      #
      # The generated subclass is MCP-transport-only, unlike Axn::MCP::Tool: its .call always
      # returns MCP::Tool::Response (never a raw Axn::Result), and it deliberately has no .call! --
      # MCP::Server itself only ever calls .call, and a consumer wanting real bang/raise-on-failure
      # semantics can call the original wrapped class's own .call! directly (unwrapped).
      def wrap(axn_class, description:, name: nil, annotations: nil, mcp_text_content: Axn::MCP.config.mcp_text_content)
        Class.new(::MCP::Tool) do
          tool_name(name) if name
          description(description)

          input_schema(Axn::Reflection::Schema.build_input(axn_class.internal_field_configs, axn_class.subfield_configs))
          output_schema(Axn::Reflection::Schema.build_output(axn_class.external_field_configs)) unless axn_class.external_field_configs.empty?

          hint_annotations = Axn::MCP::Annotations.annotations_for(axn_class._semantic_hints)
          self.annotations(**(annotations || hint_annotations)) if annotations || hint_annotations.any?

          define_singleton_method(:call) do |**kwargs|
            Axn::MCP::Invocation.perform(axn_class, kwargs, text_content: mcp_text_content)
          end
        end
      end
    end
  end
end
