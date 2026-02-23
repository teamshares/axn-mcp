# frozen_string_literal: true

module Axn
  module MCP
    module SchemaBuilder
      TYPE_MAP = {
        String => "string",
        Integer => "integer",
        Float => "number",
        Numeric => "number",
        Hash => "object",
        Array => "array",
        TrueClass => "boolean",
        FalseClass => "boolean",
        Date => "string",
        DateTime => "string",
        Time => "string",
      }.freeze

      FORMAT_MAP = {
        Date => "date",
        DateTime => "date-time",
        Time => "date-time",
      }.freeze

      EXCLUDED_FROM_SCHEMA = %i[server_context].freeze

      module_function

      def build_input(field_configs, subfield_configs = [])
        properties = {}
        required = []

        subfields_by_parent = subfield_configs.group_by(&:on)

        field_configs.each do |config|
          next if EXCLUDED_FROM_SCHEMA.include?(config.field)

          if config.validations[:model]
            build_model_property(config, properties, required)
          else
            prop = build_property(config)
            nested_subfields = subfields_by_parent[config.field]
            if nested_subfields&.any? && prop[:type] == "object"
              prop[:properties] ||= {}
              prop[:required] ||= []
              nested_subfields.each do |subconfig|
                subprop = build_property(subconfig)
                prop[:properties][subconfig.field] = subprop
                prop[:required] << subconfig.field.to_s unless optional?(subconfig)
              end
              prop[:required] = nil if prop[:required].empty?
            end

            properties[config.field] = prop.compact
            required << config.field.to_s unless optional?(config)
          end
        end

        schema = { type: "object", properties: }
        schema[:required] = required unless required.empty?
        schema
      end

      def build_output(field_configs)
        properties = {}
        required = []

        field_configs.each do |config|
          prop = build_property(config, for_output: true)
          properties[config.field] = prop.compact
          required << config.field.to_s unless optional?(config)
        end

        schema = { type: "object", properties: }
        schema[:required] = required unless required.empty?
        schema
      end

      def build_property(config, for_output: false)
        prop = {}
        prop[:description] = config.description if config.description

        type_info = json_type_for(config.validations, for_output:)
        prop[:type] = type_info[:type] if type_info[:type]
        prop[:format] = type_info[:format] if type_info[:format]

        prop[:default] = config.default unless config.default.nil?

        if (inclusion = config.validations[:inclusion])
          enum_values = inclusion[:in] || inclusion[:within] if inclusion.is_a?(Hash)
          prop[:enum] = enum_values if enum_values
        end

        prop
      end

      def build_model_property(config, properties, required)
        model_opts = config.validations[:model]
        klass = model_opts[:klass]
        klass_name = klass.is_a?(Class) ? klass.name : klass.to_s

        id_field = :"#{config.field}_id"
        prop = {
          type: "integer",
          description: config.description || "ID of the #{klass_name} record",
        }

        properties[id_field] = prop.compact
        required << id_field.to_s unless optional?(config)
      end

      def json_type_for(validations, for_output: false)
        if validations[:type]
          type_opt = validations[:type]
          klass = type_opt.is_a?(Hash) ? type_opt[:klass] : type_opt
          klasses = Array(klass)

          klass = klasses.first
          return { type: "boolean" } if klass == :boolean
          return { type: "string", format: "uuid" } if klass == :uuid

          if TYPE_MAP.key?(klass)
            result = { type: TYPE_MAP[klass] }
            result[:format] = FORMAT_MAP[klass] if FORMAT_MAP.key?(klass)
            return result
          end

          return { type: "object" } if for_output

          return { type: "string" }
        end

        if validations[:inclusion]
          inclusion = validations[:inclusion]
          enum_values = inclusion[:in] || inclusion[:within] if inclusion.is_a?(Hash)
          if enum_values&.any?
            sample = enum_values.first
            return { type: "string" } if sample.is_a?(String)
            return { type: "integer" } if sample.is_a?(Integer)
            return { type: "number" } if sample.is_a?(Float)
          end
        end

        if validations[:numericality]
          numericality = validations[:numericality]
          return { type: "integer" } if numericality.is_a?(Hash) && numericality[:only_integer]

          return { type: "number" }
        end

        return { type: "string" } if validations[:presence] || validations[:length]

        {}
      end

      def optional?(config)
        Axn::Internal::FieldConfig.optional?(config)
      end
    end
  end
end
