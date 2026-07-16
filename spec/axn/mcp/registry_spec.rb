# frozen_string_literal: true

# PRO-2923: axn-mcp registers itself as a tool adapter with axn core's process-global tool
# registry, so a consumer can enumerate its MCP tools via `Axn.tools_for(:mcp)` instead of
# hand-maintaining an array.
RSpec.describe "Axn::MCP tool-adapter registration" do
  it "registers the :mcp adapter with axn core at load" do
    expect(Axn::Tools::Registry.adapters).to include(:mcp)
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

    it "honors a per-class configure(:mcp) override at wrap time" do
      stub_const("ConfiguredToolsTool", Class.new do
        include Axn

        tool :mcp
        description "Configured tool"
        exposes :greeting, type: String
        def call = expose(greeting: "hi")
        configure(:mcp) { |c| c.mcp_text_content = :message }
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
