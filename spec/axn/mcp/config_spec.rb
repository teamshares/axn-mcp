# frozen_string_literal: true

RSpec.describe "Axn::MCP configuration" do
  around do |example|
    original = Axn::MCP.config.mcp_text_content
    example.run
  ensure
    Axn::MCP.config.mcp_text_content = original
  end

  describe "Axn::MCP.config.mcp_text_content=" do
    it "accepts :structured" do
      Axn::MCP.config.mcp_text_content = :structured
      expect(Axn::MCP.config.mcp_text_content).to eq(:structured)
    end

    it "accepts :message" do
      Axn::MCP.config.mcp_text_content = :message
      expect(Axn::MCP.config.mcp_text_content).to eq(:message)
    end

    it "raises ArgumentError for invalid value" do
      expect { Axn::MCP.config.mcp_text_content = :invalid }.to raise_error(ArgumentError, /mcp_text_content must be one of/)
      expect { Axn::MCP.config.mcp_text_content = :success }.to raise_error(ArgumentError, /mcp_text_content must be one of/)
    end
  end

  describe "Axn::MCP.configure" do
    it "yields the config for assignment" do
      Axn::MCP.configure { |c| c.mcp_text_content = :message }
      expect(Axn::MCP.config.mcp_text_content).to eq(:message)
    end
  end

  describe "default" do
    it "defaults mcp_text_content to :structured" do
      Axn::MCP.reset_config!
      expect(Axn::MCP.config.mcp_text_content).to eq(:structured)
    end
  end
end
