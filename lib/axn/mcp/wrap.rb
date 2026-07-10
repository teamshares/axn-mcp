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
      VALID_MCP_TEXT_CONTENT = %i[structured message].freeze

      def wrap(axn_class, description:, name: nil, annotations: nil, mcp_text_content: nil)
        # Fail fast on a typo'd value (e.g. :mesage) rather than silently falling through to
        # :structured -- matches the validation Axn::MCP.config.mcp_text_content=/Tool's
        # mcp_text_content(...) setting already enforce (same error message shape).
        if mcp_text_content && !VALID_MCP_TEXT_CONTENT.include?(mcp_text_content)
          raise ArgumentError, "mcp_text_content must be one of #{VALID_MCP_TEXT_CONTENT.map(&:inspect).join(", ")}; got #{mcp_text_content.inspect}"
        end

        Class.new(::MCP::Tool) do
          tool_name(name) if name
          description(description)

          input_schema(Axn::Reflection::Schema.build_input(axn_class.internal_field_configs, axn_class.subfield_configs))
          output_schema(Axn::Reflection::Schema.build_output(axn_class.external_field_configs)) unless axn_class.external_field_configs.empty?

          hint_annotations = Axn::MCP::Annotations.annotations_for(axn_class._semantic_hints)
          self.annotations(**(annotations || hint_annotations)) if annotations || hint_annotations.any?

          define_singleton_method(:call) do |**kwargs|
            # Resolved fresh on every call (mcp_text_content || Axn::MCP.config...), not captured
            # once at wrap-time, so this matches Axn::MCP::Tool#call's resolved_mcp_text_content
            # guarantee: a gem-wide config change takes effect immediately, even for tools already
            # wrapped before the change.
            Axn::MCP::Invocation.perform(axn_class, kwargs, text_content: mcp_text_content || Axn::MCP.config.mcp_text_content)
          end
        end
      end
    end
  end
end
