# frozen_string_literal: true

RSpec.describe Axn::MCP::Invocation do
  describe ".perform" do
    it "maps server_context into ambient_context, not a top-level kwarg" do
      axn_class = Class.new do
        include Axn

        expects :name, type: String
        expects :server_context, on: :ambient_context, type: Hash, optional: true
        exposes :seen_context, type: Hash, optional: true

        def call
          expose seen_context: server_context
        end
      end

      response = described_class.perform(axn_class, { name: "Alice", server_context: { user_id: 1 } }, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen_context"]).to eq("user_id" => 1)
    end

    it "passes ambient_context: nil explicitly (not omitted) when server_context is nil, so no Current default leaks in" do
      axn_class = Class.new do
        include Axn

        expects :leaky, on: :ambient_context, type: String, optional: true
        exposes :res, type: String, optional: true
        def call = expose(res: leaky)
      end

      response = described_class.perform(axn_class, {}, text_content: :structured)
      expect(JSON.parse(response.content.first[:text])["res"]).to be_nil
    end

    it "does not let a caller-supplied ambient_context kwarg override the server-injected one" do
      axn_class = Class.new do
        include Axn

        expects :server_context, on: :ambient_context, type: Hash, optional: true
        exposes :seen_context, type: Hash, optional: true

        def call
          expose seen_context: server_context
        end
      end

      forged = { server_context: { user_id: "attacker" } }
      response = described_class.perform(axn_class, { ambient_context: forged, server_context: { user_id: 1 } }, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen_context"]).to eq("user_id" => 1)
    end

    it "does not leak Rails Current state when server_context is absent from kwargs" do
      current_class = Class.new(ActiveSupport::CurrentAttributes) { attribute :leaky }
      stub_const("InvocationSpecCurrent", current_class)
      current_class.leaky = "should never appear"

      axn_class = Class.new do
        include Axn

        expects :leaky, on: :ambient_context, type: String, optional: true
        exposes :res, type: String, optional: true
        def call = expose(res: leaky)
      end

      response = described_class.perform(axn_class, {}, text_content: :structured)
      expect(JSON.parse(response.content.first[:text])["res"]).to be_nil
    ensure
      current_class&.reset
    end
  end
end
