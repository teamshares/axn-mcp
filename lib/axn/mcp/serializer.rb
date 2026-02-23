# frozen_string_literal: true

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

      def result_to_mcp_response(result, field_configs)
        if result.ok?
          exposed = serialize_exposed(result, field_configs)
          ::MCP::Tool::Response.new(
            [{ type: "text", text: result.message }],
            structured_content: exposed.presence,
          )
        else
          ::MCP::Tool::Response.new(
            [{ type: "text", text: result.message }],
            error: true,
          )
        end
      end
    end
  end
end
