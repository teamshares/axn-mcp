# frozen_string_literal: true

require "date"
require "axn"
require "mcp"

require_relative "mcp/version"

module Axn
  module MCP
    extend Axn::Configurable

    class SchemaError < StandardError; end

    setting :mcp_text_content, default: :structured, one_of: %i[structured message], overridable: true
  end
end

require_relative "mcp/serializer"
require_relative "mcp/schema_builder"
require_relative "mcp/field_declarations"
require_relative "mcp/tool"
