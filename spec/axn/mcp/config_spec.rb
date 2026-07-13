# frozen_string_literal: true

RSpec.describe "Axn::MCP configuration" do
  around do |example|
    original_text_content = Axn::MCP.config.mcp_text_content
    original_headline = Axn::MCP.config.error_headline
    example.run
  ensure
    Axn::MCP.config.mcp_text_content = original_text_content
    Axn::MCP.config.error_headline = original_headline
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

  describe "Axn::MCP.config.error_headline=" do
    it "accepts a non-blank String" do
      Axn::MCP.config.error_headline = "Something broke"
      expect(Axn::MCP.config.error_headline).to eq("Something broke")
    end

    it "raises ArgumentError for a blank String" do
      expect { Axn::MCP.config.error_headline = "" }.to raise_error(ArgumentError, /error_headline got invalid value/)
    end

    it "raises ArgumentError for nil" do
      expect { Axn::MCP.config.error_headline = nil }.to raise_error(ArgumentError, /error_headline got invalid value/)
    end

    it "raises ArgumentError for a non-String" do
      expect { Axn::MCP.config.error_headline = :broken }.to raise_error(ArgumentError, /error_headline got invalid value/)
    end
  end

  describe "default" do
    it "defaults mcp_text_content to :structured" do
      Axn::MCP.reset_config!
      expect(Axn::MCP.config.mcp_text_content).to eq(:structured)
    end

    it "defaults error_headline to 'Tool call failed'" do
      Axn::MCP.reset_config!
      expect(Axn::MCP.config.error_headline).to eq("Tool call failed")
    end
  end

  describe "namespaced per-class config (axn PRO-2880)" do
    it "resolves a per-tool override set via the namespaced configure(:mcp) DSL, not just the flat setter" do
      tool = Class.new(Axn::MCP::Tool) do
        def self.name = "NamespacedConfigProbe"
        def call = nil
      end

      tool.configure(:mcp) { |c| c.mcp_text_content = :message }

      expect(tool.resolved_mcp_text_content).to eq(:message)
    end

    it "lets a base Axn be configured separately for axn-mcp and another adapter composed on the same class" do
      fake_ruby_llm_adapter = Module.new do
        extend Axn::Configurable

        config_namespace :ruby_llm
        setting :temperature, default: 0.0, overridable: true
      end

      tool = Class.new(Axn::MCP::Tool) do
        include fake_ruby_llm_adapter.overrides

        def self.name = "MultiAdapterProbe"
        def call = nil
      end

      tool.configure(:mcp) { |c| c.mcp_text_content = :message }
      tool.configure(:ruby_llm) { |c| c.temperature = 0.2 }

      expect(tool.resolved_mcp_text_content).to eq(:message)
      expect(tool.resolved_temperature).to eq(0.2)
    end
  end
end
