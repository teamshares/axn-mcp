# frozen_string_literal: true

require "json"
require "active_support/core_ext/object/blank"

module Axn
  module MCP
    module Serializer
      module_function

      def result_to_mcp_response(result, text_content: :structured, reject_opaque_exposed_values: false)
        if result.ok?
          exposed = Axn::Extensions::Serialization.render(result, reject_opaque: reject_opaque_exposed_values)
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
