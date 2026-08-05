# frozen_string_literal: true

module Axn
  module MCP
    # RETIRED (PRO-2923): the `Axn::MCP::Tool` subclass base has been removed.
    #
    # It previously wrapped `include Axn` + `::MCP::Tool` into a dual-mode base whose `.call`
    # returned either an `Axn::Result` (called directly) or an `MCP::Tool::Response` (called with
    # `server_context:`). That dual mode also overrode `input_schema` to a non-Hash
    # `MCP::Tool::InputSchema`, which broke `Axn::RubyLLM.wrap` on the same class. The author-once
    # model replaces it: write a plain Axn and expose it with `Axn::MCP.wrap` (per tool) or
    # `Axn::MCP.tools` (every registered `:mcp` tool at once).
    #
    # Kept only as a raising tombstone so leftover `class MyTool < Axn::MCP::Tool` / `.define` code
    # fails with a migration message instead of a bare `NameError`/`NoMethodError`. See
    # DEPRECATIONS.md — this constant is slated for deletion at 1.0.
    class Tool
      MIGRATION_MESSAGE = <<~MSG
        Axn::MCP::Tool (subclass base) and Axn::MCP::Tool.define were retired in PRO-2923.

        Instead of subclassing:

            class MyTool < Axn::MCP::Tool
              expects :query, type: String
              exposes :results, type: Array
              def call = expose(results: Item.search(query))
            end

        author a plain Axn and expose it with Axn::MCP.wrap:

            class MyTool
              include Axn
              tool :mcp                       # optional: discoverable via Axn::MCP.tools
              expects :query, type: String
              exposes :results, type: Array
              def call = expose(results: Item.search(query))
            end

            Axn::MCP.wrap(MyTool)             # -> a ready-to-register ::MCP::Tool subclass
            # ...or register every :mcp tool at once:
            MCP::Server.new(name: "...", version: "...", tools: Axn::MCP.tools)

        For a one-off inline tool (the old .define use case), wrap an Axn::Factory.build:

            Axn::MCP.wrap(
              Axn::Factory.build(expects: { query: { type: String } },
                                 exposes: { results: { type: Array } }) { expose results: Item.search(query) },
              name: "search", description: "Search for items",
            )

        See DEPRECATIONS.md.
      MSG

      def self.inherited(subclass)
        super
        raise NotImplementedError, MIGRATION_MESSAGE
      end

      def self.define(*, **, &)
        raise NotImplementedError, MIGRATION_MESSAGE
      end
    end
  end
end
