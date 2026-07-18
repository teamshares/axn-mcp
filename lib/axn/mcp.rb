# frozen_string_literal: true

require "date"
require "axn"
require "mcp"
require "active_support/deprecation"
require "active_support/isolated_execution_state"

require_relative "mcp/version"
Axn.extension_config.register_semantic_hint(:open_world, :closed_world)

module Axn
  module MCP
    extend Axn::Configurable
    extend Axn::Tools::AdapterRoots

    config_namespace :mcp

    class SchemaError < StandardError; end

    # `extend Axn::Tools::AdapterRoots` declares a validated `tool_roots` directory list (default
    # []); the registry reads `Axn::MCP.config.tool_roots` for directory-based tool membership.
    # Ship the shared `agent_tools` convention as the default root, so an Axn under `app/agent_tools/`
    # is exposed as an MCP tool out of the box (no explicit `tool :mcp` needed) -- and, since
    # axn-ruby_llm defaults to the same dir, the same tool is exposed over ruby_llm too. Re-declaring
    # the setting overrides AdapterRoots' empty default while reusing its broad-path validation
    # (which rejects widening a root to `app/`/`.`/`actions`/a `..` traversal).
    setting :tool_roots, default: %w[agent_tools], validate: ->(value) { Axn::Tools::AdapterRoots.validate!(value) }

    setting :present_as, default: :structured, one_of: %i[structured message], overridable: true

    # Per-tool MCP metadata, declarable on the class via `configure(:mcp) { |c| c.title = "..." }`
    # so it survives the zero-arg `Axn::MCP.tools` path (which calls `wrap` with no kwargs). Each
    # defaults to nil -- left at `::MCP::Tool`'s own default unless set -- and an explicit `wrap`
    # kwarg still wins over the configured value. Loosely typed (no validation here); `::MCP::Tool`
    # validates the shapes when they're applied.
    setting :title, default: nil, overridable: true
    setting :icons, default: nil, overridable: true
    setting :meta, default: nil, overridable: true
    setting :annotations, default: nil, overridable: true

    # Shared deprecator for this gem's own deprecated API (e.g. the legacy annotation
    # bang-methods -- see lib/axn/mcp/tool.rb). A dedicated ActiveSupport::Deprecation instance,
    # not the old global ActiveSupport::Deprecation.warn, so a consuming Rails app can register it
    # (`Rails.application.deprecators[:axn_mcp] = Axn::MCP.deprecator`) and govern its behavior
    # (silence in test, raise in CI, etc.) the same way it already does for its own deprecations.
    def self.deprecator
      @deprecator ||= ActiveSupport::Deprecation.new("1.0", "axn-mcp")
    end

    # The live MCP server context for the current wrapped-tool call -- an `MCP::ServerContext` over a
    # real `MCP::Server`, or whatever raw value was passed as `server_context:` to a direct call --
    # or `nil` outside a wrapped `#call`. This is the MCP-specific handle for transport *capabilities*
    # (`Axn::MCP.server_context.report_progress(...)`, `.cancelled?`), which are not ambient data and
    # don't survive `ambient_context`'s declared-key filtering. Ambient *data* still belongs in
    # `ambient_context` (`expects :user_id, on: :ambient_context`), which `wrap` spreads from the same
    # server_context and which stays adapter-agnostic. A tool reaching for this is knowingly
    # MCP-coupled -- appropriate, since these operations are MCP-transport-only.
    def self.server_context
      ActiveSupport::IsolatedExecutionState[:__axn_mcp_server_context]
    end

    # Sets Axn::MCP.server_context for the duration of the block. Uses ActiveSupport's
    # IsolatedExecutionState (thread- or fiber-scoped per the configured isolation_level), matching
    # how axn core scopes its own per-execution state and CurrentAttributes -- so this stays correct
    # under a Fiber scheduler rather than silently leaking across fibers a raw Thread-local would.
    # Restores the previous value on the way out so nested wrapped calls compose.
    def self.with_server_context(value)
      previous = ActiveSupport::IsolatedExecutionState[:__axn_mcp_server_context]
      ActiveSupport::IsolatedExecutionState[:__axn_mcp_server_context] = value
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[:__axn_mcp_server_context] = previous
    end

    # Register :mcp with axn core's process-global tool registry, passing this module as the config
    # source (PRO-2943/PRO-2944) so the registry reads `Axn::MCP.config.tool_roots` for
    # directory-based membership. A consumer builds its server tool list from `Axn::MCP.tools`
    # (`Axn.tools_for(:mcp)`) -- resolving directory-root grants, an explicit `tool`/`tool :mcp`
    # declaration, and implicit `configure(:mcp)` membership -- instead of a hand-maintained array.
    Axn.register_tool_adapter(:mcp, self)
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
