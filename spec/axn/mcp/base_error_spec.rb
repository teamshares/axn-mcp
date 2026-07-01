# frozen_string_literal: true

require "spec_helper"

# Pins down the exact failure strings produced by Axn::MCP::Tool's base error headline (default
# "Tool call failed", configurable via Axn::MCP.config.error_headline) across every failure mode,
# and guards against awkward prefix/suffix joining.
RSpec.describe "Axn::MCP::Tool base error headline" do
  # Resolve the failure presentation the way the serializer does (result.error), for an
  # anonymous tool whose #call body is the given block.
  def failure_text(&blk)
    tool = Class.new(Axn::MCP::Tool, &blk)
    result = tool.call
    expect(result).not_to be_ok
    result.error
  end

  describe "with no explicit reason (base headline stands alone)" do
    it "replaces axn's generic default on a bare fail!" do
      expect(failure_text { def call = fail! }).to eq("Tool call failed")
    end

    it "uses the headline alone for an empty-string reason (no dangling delimiter)" do
      expect(failure_text { def call = fail!("") }).to eq("Tool call failed")
    end

    it "uses the headline alone for a missing required field" do
      text = failure_text do
        expects :name, type: String
        def call = nil
      end
      expect(text).to eq("Tool call failed")
    end

    it "uses the headline alone for a type-mismatched field" do
      tool = Class.new(Axn::MCP::Tool) do
        expects :count, type: Integer
        def call = nil
      end
      result = tool.call(count: "abc")
      expect(result).not_to be_ok
      expect(result.exception).to be_a(Axn::InboundValidationError)
      expect(result.error).to eq("Tool call failed")
    end

    it "uses the headline alone for an unexpected raised exception (no internal detail leaked)" do
      expect(failure_text { def call = raise(StandardError, "boom") }).to eq("Tool call failed")
    end
  end

  describe "with an explicit fail! reason (headline prefixes the reason)" do
    it "joins headline and reason with ': '" do
      expect(failure_text { def call = fail!("email taken") }).to eq("Tool call failed: email taken")
    end

    it "does not mangle a reason that itself contains a colon" do
      expect(failure_text { def call = fail!("not found: user 5") }).to eq("Tool call failed: not found: user 5")
    end

    it "honors standalone: true to emit the reason on its own" do
      expect(failure_text { def call = fail!("Account is locked.", standalone: true) }).to eq("Account is locked.")
    end
  end

  describe "gem-wide configurability (Axn::MCP.config.error_headline)" do
    around do |example|
      original = Axn::MCP.config.error_headline
      example.run
    ensure
      Axn::MCP.config.error_headline = original
    end

    it "uses a reconfigured headline immediately, with no reload of the Tool class" do
      tool = Class.new(Axn::MCP::Tool) { def call = fail!("email taken") }
      expect(tool.call.error).to eq("Tool call failed: email taken")

      Axn::MCP.config.error_headline = "Something broke"

      expect(tool.call.error).to eq("Something broke: email taken")
    end

    it "still lets a subclass's own base error win over the configured headline" do
      Axn::MCP.config.error_headline = "Something broke"
      tool = Class.new(Axn::MCP::Tool) do
        error "Couldn't sync user"
        def call = fail!("email taken")
      end

      expect(tool.call.error).to eq("Couldn't sync user: email taken")
    end

    it "rejects a blank or non-String headline at assignment" do
      expect { Axn::MCP.config.error_headline = "" }.to raise_error(ArgumentError, /error_headline/)
      expect { Axn::MCP.config.error_headline = nil }.to raise_error(ArgumentError, /error_headline/)
    end
  end

  describe "presentation across .call / .call!" do
    let(:tool) { Class.new(Axn::MCP::Tool) { def call = fail!("email taken") } }

    it "exposes the prefixed presentation via result.error/#message" do
      result = tool.call
      expect(result.error).to eq("Tool call failed: email taken")
      expect(result.message).to eq("Tool call failed: email taken")
    end

    it "raises with #message matching result.error on call! (Axn-owned exception)" do
      expect { tool.call! }.to raise_error(Axn::Failure, "Tool call failed: email taken")
    end
  end

  describe "subclass behavior" do
    it "lets a subclass override the headline with its own base error" do
      parent = Class.new(Axn::MCP::Tool)
      child = Class.new(parent) do
        error "Couldn't sync user"
        def call = fail!("email taken")
      end
      expect(child.call.error).to eq("Couldn't sync user: email taken")
    end

    it "inherits the base headline when a subclass does not redeclare it" do
      parent = Class.new(Axn::MCP::Tool)
      child = Class.new(parent) { def call = fail!("email taken") }
      expect(child.call.error).to eq("Tool call failed: email taken")
    end
  end

  describe "through the MCP response (server_context present)" do
    it "passes the prefixed text through and flags the response as an error" do
      tool = Class.new(Axn::MCP::Tool) { def call = fail!("email taken") }
      response = tool.call(server_context: { user_id: 1 })

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be true
      expect(response.content.first[:text]).to eq("Tool call failed: email taken")
    end

    it "passes the standalone headline through for a no-reason failure" do
      tool = Class.new(Axn::MCP::Tool) { def call = raise(StandardError, "boom") }
      response = tool.call(server_context: { user_id: 1 })

      expect(response.error?).to be true
      expect(response.content.first[:text]).to eq("Tool call failed")
    end
  end
end
