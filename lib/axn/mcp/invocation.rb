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
        rest = kwargs.except(:server_context)

        result = axn_class.call(ambient_context: { server_context: }, **rest)
        Serializer.result_to_mcp_response(result, axn_class.external_field_configs, text_content:)
      end
    end
  end
end
