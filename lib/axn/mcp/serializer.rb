# frozen_string_literal: true

require "json"
require "active_support/core_ext/object/blank"

module Axn
  module MCP
    module Serializer
      module_function

      def serialize_exposed(result, field_configs)
        field_configs.each_with_object({}) do |config, hash|
          value = result.public_send(config.field)
          hash[config.field.to_s] = serialize_value(value)
        end
      end

      def serialize_value(value)
        case value
        when nil, String, Integer, Float, TrueClass, FalseClass
          value
        when Hash
          value.transform_keys(&:to_s).transform_values { |v| serialize_value(v) }
        when Array
          value.map { |v| serialize_value(v) }
        else
          if value.respond_to?(:as_json)
            value.as_json
          elsif value.respond_to?(:to_h)
            serialize_value(value.to_h)
          else
            value.to_s
          end
        end
      end

      def result_to_mcp_response(result, field_configs, text_content: :structured)
        if result.ok?
          exposed = serialize_exposed(result, field_configs)
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
