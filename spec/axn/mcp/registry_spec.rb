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
