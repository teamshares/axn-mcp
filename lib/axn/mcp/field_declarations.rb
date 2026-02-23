# frozen_string_literal: true

module Axn
  module MCP
    module FieldDeclarations
      module_function

      def hydrate(declarations)
        return declarations if declarations.is_a?(Hash)

        Array(declarations).each_with_object({}) do |item, acc|
          if item.is_a?(Hash)
            item.each { |k, v| acc[k] = v }
          else
            acc[item] = {}
          end
        end
      end
    end
  end
end
