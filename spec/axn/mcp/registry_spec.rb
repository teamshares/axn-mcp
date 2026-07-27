# frozen_string_literal: true

# PRO-2923: axn-mcp registers itself as a tool adapter with axn core's process-global tool
# registry, so a consumer can enumerate its MCP tools via `Axn.tools_for(:mcp)` instead of
# hand-maintaining an array.
RSpec.describe "Axn::MCP tool-adapter registration" do
  it "registers the :mcp adapter with axn core at load" do
    expect(Axn::Tools::Registry.adapters).to include(:mcp)
  end

  describe "tool_roots / adapter config source (PRO-2943/PRO-2944)" do
    after { Axn::MCP.reset_config! }

    it "ships `agent_tools` as the default tool_roots (shared with axn-ruby_llm)" do
      expect(Axn::MCP.config.tool_roots).to eq(["agent_tools"])
    end

    it "registers Axn::MCP as the :mcp adapter's config source, so the registry reads its tool_roots" do
      expect(Axn::Tools::Registry.adapter_config_source(:mcp)).to eq(Axn::MCP)

      Axn::MCP.config.tool_roots = ["actions/mcp_tools"]
      expect(Axn::Tools::Registry.adapter_config_source(:mcp).config.tool_roots).to eq(["actions/mcp_tools"])
    end

    it "rejects a broad tool_roots entry that would bulk-expose every business action" do
      expect { Axn::MCP.config.tool_roots = ["app"] }.to raise_error(ArgumentError, /too broad/)
    end
  end

  it "lets a consumer enumerate :mcp tools via Axn.tools_for(:mcp)" do
    stub_const("EnumerableMcpTool", Class.new do
      include Axn

      tool :mcp
      exposes :x, type: String
      def call = expose(x: "y")
    end)

    expect(Axn.tools_for(:mcp)).to include(EnumerableMcpTool)
  end

  describe "Axn::MCP.tools" do
    it "returns wrapped, ready-to-register ::MCP::Tool subclasses for every registered :mcp tool" do
      stub_const("ToolsListTool", Class.new do
        include Axn

        tool :mcp
        description "Listed tool"
        exposes :x, type: String
        def call = expose(x: "y")
      end)

      listed = Axn::MCP.tools.find { |t| t.name_value == "tools_list_tool" }

      expect(listed).not_to be_nil
      expect(listed).to be < MCP::Tool
      expect(listed.description).to eq("Listed tool") # zero-arg: description derived from the Axn
    end

    it "returns tools deterministically ordered by tool_name (via core's tools_for sort)" do
      # Registered out of alphabetical order; core's tools_for sorts by tool_name, so Axn::MCP.tools
      # is stable regardless of load/registration order (a property both adapter gems inherit).
      stub_const("ZzzOrderingTool", Class.new do
        include Axn

        tool(:mcp)
        exposes(:x, type: String)
        def call = expose(x: "y")
      end)

      stub_const("AaaOrderingTool", Class.new do
        include Axn

        tool(:mcp)
        exposes(:x, type: String)
        def call = expose(x: "y")
      end)

      stub_const("MmmOrderingTool", Class.new do
        include Axn

        tool(:mcp)
        exposes(:x, type: String)
        def call = expose(x: "y")
      end)

      mine = Axn::MCP.tools.map(&:name_value).select { |n| n.end_with?("_ordering_tool") }

      expect(mine).to eq(%w[aaa_ordering_tool mmm_ordering_tool zzz_ordering_tool])
    end

    it "wraps only the latest version when two tools share a tool_name (PRO-2955)" do
      # tool_version is identity-distinct from tool_name (core strips the V1/V2 segment, so both
      # derive tool_name "thing"). Axn.tools_for(:mcp) collapses a shared tool_name to its highest
      # tool_version, so Axn::MCP.tools -- a plain `.map { wrap }` over it -- exposes only V2.
      stub_const("AgentTools::Thing::V1", Class.new do
        include Axn

        tool :mcp
        tool_version 1
        description "thing v1"
        exposes :x, type: String
        def call = expose(x: "v1")
      end)

      stub_const("AgentTools::Thing::V2", Class.new do
        include Axn

        tool :mcp
        tool_version 2
        description "thing v2"
        exposes :x, type: String
        def call = expose(x: "v2")
      end)

      versioned = Axn::MCP.tools.select { |t| t.name_value == "thing" }

      expect(versioned.size).to eq(1) # V1 superseded, not a second tool under the same name
      expect(versioned.first.description).to eq("thing v2") # description derived from V2, the latest
    end

    it "honors a per-class configure(:mcp) override at wrap time" do
      stub_const("ConfiguredToolsTool", Class.new do
        include Axn

        tool :mcp
        description "Configured tool"
        exposes :greeting, type: String
        def call = expose(greeting: "hi")
        configure(:mcp) { |c| c.present_as = :message }
      end)

      listed = Axn::MCP.tools.find { |t| t.name_value == "configured_tools_tool" }
      response = listed.call(greeting_ignored: nil, server_context: {})

      expect(response.content.first[:text]).to eq("Action completed successfully")
    end
  end

  it "each enumerated tool can be handed straight to Axn::MCP.wrap" do
    stub_const("WrappableMcpTool", Class.new do
      include Axn

      tool :mcp
      description "A wrappable tool"
      exposes :x, type: String
      def call = expose(x: "y")
    end)

    tools = Axn.tools_for(:mcp).select { |t| t == WrappableMcpTool }
    wrapped = tools.map { |t| Axn::MCP.wrap(t) }

    expect(wrapped.first).to be < MCP::Tool
    expect(wrapped.first.name_value).to eq("wrappable_mcp_tool")
  end
end
