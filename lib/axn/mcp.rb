# frozen_string_literal: true

require "date"
require "axn"
require "mcp"

require_relative "mcp/version"
Axn.extension_config.register_semantic_hint(:open_world, :closed_world)

module Axn
  module MCP
    extend Axn::Configurable

    class SchemaError < StandardError; end

    setting :mcp_text_content, default: :structured, one_of: %i[structured message], overridable: true
    setting :error_headline, default: "Tool call failed", validate: ->(v) { v.is_a?(String) && !v.strip.empty? }
  end
end

# Required after the module above extends Axn::Configurable, since Tool calls
# Axn::MCP.overrides at class-definition time. (Setting declaration order is
# free, but the extend must happen first.)
require_relative "mcp/annotations"
require_relative "mcp/serializer"
require_relative "mcp/field_declarations"
require_relative "mcp/invocation"
require_relative "mcp/tool"
