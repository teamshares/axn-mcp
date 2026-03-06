# frozen_string_literal: true

module Axn
  module MCP
    class Config
      VALID_MCP_TEXT_CONTENT = %i[structured message].freeze

      attr_reader :mcp_text_content

      def initialize
        @mcp_text_content = :structured
      end

      def mcp_text_content=(value)
        self.class.validate_mcp_text_content!(value)
        @mcp_text_content = value
      end

      def self.validate_mcp_text_content!(value)
        return if VALID_MCP_TEXT_CONTENT.include?(value)

        raise ArgumentError,
              "mcp_text_content must be one of #{VALID_MCP_TEXT_CONTENT.map(&:inspect).join(", ")}; got #{value.inspect}"
      end
    end
  end
end
