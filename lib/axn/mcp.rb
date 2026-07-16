# frozen_string_literal: true

require "date"
require "axn"
require "mcp"
require "active_support/deprecation"

require_relative "mcp/version"
Axn.extension_config.register_semantic_hint(:open_world, :closed_world)

# Register :mcp as a tool adapter with axn core's process-global registry (PRO-2923), so a
# consumer can build its server tool list from `Axn.tools_for(:mcp)` -- resolving bare `tool`
# membership, `tool :mcp`, and implicit `configure(:mcp)` membership -- instead of a
# hand-maintained array.
Axn.register_tool_adapter(:mcp)

module Axn
  module MCP
    extend Axn::Configurable

    config_namespace :mcp

    class SchemaError < StandardError; end

    setting :mcp_text_content, default: :structured, one_of: %i[structured message], overridable: true
    setting :error_headline, default: "Tool call failed", validate: ->(v) { v.is_a?(String) && !v.strip.empty? }

    # Shared deprecator for this gem's own deprecated API (e.g. the legacy annotation
    # bang-methods -- see lib/axn/mcp/tool.rb). A dedicated ActiveSupport::Deprecation instance,
    # not the old global ActiveSupport::Deprecation.warn, so a consuming Rails app can register it
    # (`Rails.application.deprecators[:axn_mcp] = Axn::MCP.deprecator`) and govern its behavior
    # (silence in test, raise in CI, etc.) the same way it already does for its own deprecations.
    def self.deprecator
      @deprecator ||= ActiveSupport::Deprecation.new("1.0", "axn-mcp")
    end
  end
end

# Required after the module above extends Axn::Configurable, since Tool calls
# Axn::MCP.overrides at class-definition time. (Setting declaration order is
# free, but the extend must happen first.)
require_relative "mcp/annotations"
require_relative "mcp/serializer"
require_relative "mcp/invocation"
require_relative "mcp/tool"
require_relative "mcp/wrap"
