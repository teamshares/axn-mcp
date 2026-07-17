# frozen_string_literal: true

RSpec.describe Axn::MCP::Invocation do
  describe ".perform" do
    # A generic, adapter-agnostic Axn: declares the ambient data it needs directly (no MCP-specific
    # `server_context` intermediate), so the same class works under any adapter or a direct call.
    def user_id_axn
      Class.new do
        include Axn

        expects :name, type: String, optional: true
        expects :user_id, on: :ambient_context, type: Object, optional: true
        exposes :seen, optional: true
        def call = expose(seen: user_id)
      end
    end

    it "spreads server_context as the Axn's ambient_context (declared fields resolve from it)" do
      response = described_class.perform(user_id_axn, { name: "Alice", server_context: { user_id: 1 } }, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen"]).to eq(1)
    end

    it "spreads server_context arriving under a string key too" do
      response = described_class.perform(user_id_axn, { "name" => "Alice", "server_context" => { user_id: 1 } }, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen"]).to eq(1)
    end

    it "prefers an explicit nil symbol-keyed server_context over a forged string-keyed one" do
      forged = { user_id: "attacker" }
      response = described_class.perform(user_id_axn, { server_context: nil, "server_context" => forged }, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen"]).to be_nil
    end

    it "passes an explicit empty ambient_context when server_context is absent, so no Current default leaks in" do
      response = described_class.perform(user_id_axn, {}, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen"]).to be_nil
    end

    it "does not let a caller-supplied ambient_context kwarg override the server-injected one" do
      forged = { user_id: "attacker" }
      response = described_class.perform(user_id_axn, { ambient_context: forged, server_context: { user_id: 1 } }, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen"]).to eq(1)
    end

    it "does not let a caller-supplied ambient_context kwarg override the injected one, even with a string key" do
      forged = { user_id: "attacker" }
      response = described_class.perform(user_id_axn, { "ambient_context" => forged, server_context: { user_id: 1 } }, text_content: :structured)

      expect(JSON.parse(response.content.first[:text])["seen"]).to eq(1)
    end

    it "does not leak Rails Current state when server_context is absent from kwargs" do
      current_class = Class.new(ActiveSupport::CurrentAttributes) { attribute :user_id }
      stub_const("InvocationSpecCurrent", current_class)
      current_class.user_id = "should never appear"

      response = described_class.perform(user_id_axn, {}, text_content: :structured)
      expect(JSON.parse(response.content.first[:text])["seen"]).to be_nil
    ensure
      current_class&.reset
    end

    describe "Axn::MCP.server_context (transport-capability handle)" do
      it "exposes the raw server_context object to the Axn during the call, and nil outside it" do
        seen_class = Axn::MCP.server_context # nil before any call

        capability_axn = Class.new do
          include Axn

          exposes :progress, optional: true
          def call = expose(progress: Axn::MCP.server_context&.report_progress)
        end

        server_context = Object.new
        def server_context.report_progress = "PROGRESS"

        response = described_class.perform(capability_axn, { server_context: }, text_content: :structured)

        expect(seen_class).to be_nil
        expect(JSON.parse(response.content.first[:text])["progress"]).to eq("PROGRESS")
        expect(Axn::MCP.server_context).to be_nil # restored after the call
      end
    end
  end
end
