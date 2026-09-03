# frozen_string_literal: true

require "json"
require "active_support/core_ext/object/blank"

module Axn
  module MCP
    module Serializer
      module_function

      # Client-facing text when the transport layer raises while turning a *successful* result into a
      # response (serialization, response-building — see Invocation.perform's guard). Deliberately
      # generic: the actionable detail is a gem/tool bug, so it rides on the reported exception (logs
      # / on_exception), not the tool's response — mirroring how axn keeps a failure's detail off the
      # user-facing message.
      ADAPTER_FAILURE_MESSAGE = "The tool could not produce a valid response"

      # No `reject_opaque_exposed_values:` kwarg: `Axn::MCP.serialize_exposed` (from core's
      # Axn::Tools::AdapterSerialization) resolves it per-tool off `result.__action__`'s own class, so
      # there is nothing left for a caller to pass -- or to pass wrong. Resolving one class's override
      # while rendering a different class's result is now structurally impossible.
      def result_to_mcp_response(result, text_content: :structured)
        if result.ok?
          exposed = Axn::MCP.serialize_exposed(result)
          success_text = success_response_text(result, exposed, text_content)
          ::MCP::Tool::Response.new(
            [{ type: "text", text: success_text }],
            structured_content: exposed.presence,
          )
        else
          error_response(result.error)
        end
      end

      def error_response(text)
        ::MCP::Tool::Response.new([{ type: "text", text: }], error: true)
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
