# frozen_string_literal: true

RSpec.describe Axn::MCP::Config do
  let(:config) { described_class.new }

  describe "#mcp_text_content=" do
    it "accepts :structured" do
      config.mcp_text_content = :structured
      expect(config.mcp_text_content).to eq(:structured)
    end

    it "accepts :message" do
      config.mcp_text_content = :message
      expect(config.mcp_text_content).to eq(:message)
    end

    it "raises ArgumentError for invalid value" do
      expect { config.mcp_text_content = :invalid }.to raise_error(ArgumentError, /mcp_text_content must be one of/)
      expect { config.mcp_text_content = :success }.to raise_error(ArgumentError, /mcp_text_content must be one of/)
    end
  end

  describe ".validate_mcp_text_content!" do
    it "does not raise for valid values" do
      expect { described_class.validate_mcp_text_content!(:structured) }.not_to raise_error
      expect { described_class.validate_mcp_text_content!(:message) }.not_to raise_error
    end

    it "raises ArgumentError for invalid value" do
      expect { described_class.validate_mcp_text_content!(:other) }.to raise_error(ArgumentError, /got :other/)
    end
  end

  describe "default" do
    it "defaults mcp_text_content to :structured" do
      expect(config.mcp_text_content).to eq(:structured)
    end
  end
end
