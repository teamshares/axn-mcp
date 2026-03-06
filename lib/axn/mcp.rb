# frozen_string_literal: true

require "axn"
require "mcp"

require_relative "mcp/version"
require_relative "mcp/config"
require_relative "mcp/serializer"
require_relative "mcp/schema_builder"
require_relative "mcp/field_declarations"
require_relative "mcp/tool"

module Axn
  module MCP
    class SchemaError < StandardError; end

    def self.config
      @config ||= Config.new
    end
  end
end
