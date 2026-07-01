# frozen_string_literal: true

RSpec.describe "Axn::MCP configuration" do
  around do |example|
    original_text_content = Axn::MCP.config.mcp_text_content
    original_headline = Axn::MCP.config.failure_headline
    example.run
  ensure
    Axn::MCP.config.mcp_text_content = original_text_content
    Axn::MCP.config.failure_headline = original_headline
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

  describe "Axn::MCP.config.failure_headline=" do
    it "accepts a non-blank String" do
      Axn::MCP.config.failure_headline = "Something broke"
      expect(Axn::MCP.config.failure_headline).to eq("Something broke")
    end

    it "raises ArgumentError for a blank String" do
      expect { Axn::MCP.config.failure_headline = "" }.to raise_error(ArgumentError, /failure_headline got invalid value/)
    end

    it "raises ArgumentError for nil" do
      expect { Axn::MCP.config.failure_headline = nil }.to raise_error(ArgumentError, /failure_headline got invalid value/)
    end

    it "raises ArgumentError for a non-String" do
      expect { Axn::MCP.config.failure_headline = :broken }.to raise_error(ArgumentError, /failure_headline got invalid value/)
    end
  end

  describe "default" do
    it "defaults mcp_text_content to :structured" do
      Axn::MCP.reset_config!
      expect(Axn::MCP.config.mcp_text_content).to eq(:structured)
    end

    it "defaults failure_headline to 'Tool call failed'" do
      Axn::MCP.reset_config!
      expect(Axn::MCP.config.failure_headline).to eq("Tool call failed")
    end
  end
end
