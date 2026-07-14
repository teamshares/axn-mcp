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

      def wrap(axn_class, description:, name: nil, title: nil, icons: nil, meta: nil, annotations: nil, mcp_text_content: nil)
        validate_mcp_text_content!(mcp_text_content)
        resolved_name = resolve_wrap_tool_name(axn_class, name)

        Class.new(::MCP::Tool) do
          tool_name(resolved_name)
          description(description)
          title(title) if title
          icons(icons) if icons
          meta(meta) if meta

          # axn_class.input_schema/.output_schema are axn core's own public reflection surface
          # (Axn::Core::SchemaReflection) -- wiring to those directly, rather than reaching past
          # them for the lower-level Axn::Reflection::Schema.build_input/build_output the wrapped
          # Axn's own methods already call, keeps this on the documented entry point.
          input_schema(axn_class.input_schema)
          output_schema(axn_class.output_schema) unless axn_class.external_field_configs.empty?

          hint_annotations = Axn::MCP::Annotations.annotations_for(axn_class._semantic_hints)
          self.annotations(**(annotations || hint_annotations)) if annotations || hint_annotations.any?

          define_singleton_method(:call) do |**kwargs|
            # Resolved fresh on every call (mcp_text_content || Axn::MCP.config...), not captured
            # once at wrap-time, so this matches Axn::MCP::Tool#call's own mcp_text_content read
            # guarantee: a gem-wide config change takes effect immediately, even for tools already
            # wrapped before the change.
            Axn::MCP::Invocation.perform(axn_class, kwargs, text_content: mcp_text_content || Axn::MCP.config.mcp_text_content)
          end
        end
      end

      private

      # Fail fast on any explicitly-provided invalid value (a typo like :mesage, or `false`)
      # rather than silently falling through to :structured -- matches the validation
      # Axn::MCP.config.mcp_text_content=/Tool's mcp_text_content(...) setting already enforce
      # (same error message shape). `nil` alone means "not provided" (use the gem-wide default
      # at call time) -- checked via `nil?`, not truthiness, so `mcp_text_content: false` can't
      # skip this guard the way a truthy-only check would.
      def validate_mcp_text_content!(mcp_text_content)
        return if mcp_text_content.nil? || VALID_MCP_TEXT_CONTENT.include?(mcp_text_content)

        raise ArgumentError, "mcp_text_content must be one of #{VALID_MCP_TEXT_CONTENT.map(&:inspect).join(", ")}; got #{mcp_text_content.inspect}"
      end

      # A wrap-generated class is anonymous unless the caller assigns its return value to a
      # constant -- which doesn't happen for the common `tools: [Axn::MCP.wrap(...)]` inline
      # usage. Without an explicit tool_name, ::MCP::Tool#name_value falls back to the class's
      # own (Ruby) name, which is nil for a never-assigned anonymous class, leaving the tool
      # unregisterable/unusable by MCP::Server. Derive a default from the wrapped Axn's own class
      # name (the same snake_casing ::MCP::Tool itself uses for a named class) when available,
      # and fail fast rather than silently ship an unnamed tool when it isn't.
      def resolve_wrap_tool_name(axn_class, name)
        resolved = name || (axn_class.name && ::MCP::StringUtils.handle_from_class_name(axn_class.name))
        return resolved if resolved

        raise ArgumentError, "Axn::MCP.wrap requires name: when the wrapped Axn has no derivable class name (#{axn_class}.name is nil)"
      end
    end
  end
end
