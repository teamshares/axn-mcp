# frozen_string_literal: true

RSpec.describe "Axn::MCP.wrap" do
  let(:plain_axn) do
    Class.new do
      include Axn

      def self.name = "GreetPlainly"

      expects :name, type: String
      expects :server_context, on: :ambient_context, type: Object, optional: true
      exposes :greeting, type: String

      def call
        expose greeting: "Hello, #{name}! (user #{server_context&.dig(:user_id).inspect})"
      end
    end
  end

  it "proves author-once: the original Axn is untouched and still returns Axn::Result directly" do
    result = plain_axn.call(name: "Alice")

    expect(result).to be_a(Axn::Result)
    expect(result).to be_ok
    expect(result.greeting).to eq("Hello, Alice! (user nil)")
  end

  it "wraps a plain Axn as an ::MCP::Tool subclass" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

    expect(tool).to be < MCP::Tool
    expect(tool.description).to eq("Greets someone")
    expect(tool.input_schema_value.to_h[:properties]).to have_key(:name)
    expect(tool.input_schema_value.to_h[:properties]).not_to have_key(:server_context)
  end

  it "maps server_context into the wrapped Axn's ambient_context" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

    response = tool.call(name: "Bob", server_context: { user_id: 42 })

    expect(response).to be_a(MCP::Tool::Response)
    expect(JSON.parse(response.content.first[:text])["greeting"]).to eq("Hello, Bob! (user 42)")
  end

  it "sets annotations from the wrap kwarg" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone", annotations: { read_only_hint: true })

    expect(tool.annotations_value.read_only_hint).to be true
  end

  describe "mcp_text_content resolution" do
    around do |example|
      original = Axn::MCP.config.mcp_text_content
      example.run
    ensure
      Axn::MCP.config.mcp_text_content = original
    end

    it "re-reads the gem-wide config fresh on every call, not just once at wrap-time" do
      Axn::MCP.config.mcp_text_content = :structured
      tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

      structured_response = tool.call(name: "Alice", server_context: {})
      expect(JSON.parse(structured_response.content.first[:text])).to have_key("greeting")

      Axn::MCP.config.mcp_text_content = :message
      message_response = tool.call(name: "Alice", server_context: {})
      expect(message_response.content.first[:text]).to eq("Action completed successfully")
    end
  end
end
