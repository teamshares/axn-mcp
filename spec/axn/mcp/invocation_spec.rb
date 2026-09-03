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

    describe "tool-call contract (dispatched via Axn::Tools::Invoker, PRO-3332)" do
      # `perform` now runs the wrapped Axn through Axn::Tools::Invoker.new(adapter: :mcp,
      # user_facing_input_errors: true, reject_undeclared_inputs: true) instead of a bare
      # `axn_class.call` -- matching axn-ruby_llm's and axn-openapi's own profile for the established
      # "LLM/model-facing tool" contract. Three behaviors that a bare `.call` never had:

      it "coerces a wire-typed input (a String) into the declared type -- always on, no coerce: needed" do
        coercing_axn = Class.new do
          include Axn

          expects :n, type: Integer
          exposes :doubled, type: Integer
          def call = expose(doubled: n * 2)
        end

        response = described_class.perform(coercing_axn, { n: "21", server_context: {} }, text_content: :structured)

        expect(response.error?).to be false
        expect(JSON.parse(response.content.first[:text])["doubled"]).to eq(42)
      end

      it "surfaces an inbound-contract violation as a correctable, user-facing error rather than a generic on_exception page" do
        typed_axn = Class.new do
          include Axn

          expects :n, type: Integer
          exposes :doubled, type: Integer
          def call = expose(doubled: n * 2)
        end

        reported = []
        allow(Axn.config).to receive(:on_exception) { |e, **| reported << e }

        response = described_class.perform(typed_axn, { n: "not-a-number", server_context: {} }, text_content: :structured)

        expect(response.error?).to be true
        expect(response.content.first[:text]).to match(/n/i) # names the offending field, per axn's own composition
        expect(reported).to be_empty # user-facing, per Invoker docs -- not paged as a dev-facing bug
      end

      it "rejects a top-level input the tool never declared, instead of silently dropping it" do
        no_input_axn = Class.new do
          include Axn

          exposes :done, type: :boolean
          def call = expose(done: true)
        end

        response = described_class.perform(no_input_axn, { unexpected: "value", server_context: {} }, text_content: :structured)

        expect(response.error?).to be true
        expect(response.content.first[:text]).to match(/unexpected/i)
      end

      it "stamps the call tree with the :mcp invoked_via dimension (adapter: :mcp)" do
        stamped_axn = Class.new do
          include Axn

          exposes :stamp, optional: true
          def call = expose(stamp: Axn::Internal::CurrentEntryPoint.current)
        end

        response = described_class.perform(stamped_axn, { server_context: {} }, text_content: :structured)

        expect(JSON.parse(response.content.first[:text])["stamp"]).to eq("mcp")
      end
    end

    describe "transport-failure guard (upholds axn's non-bang never-raises at the adapter boundary)" do
      # Exposes a value with no honest JSON form, so serialization raises AFTER the Axn already
      # succeeded -- in the transport layer, outside core's executor (the gap core's own on_exception
      # doesn't cover). The guard turns that into an error response + a global on_exception report.
      let(:dup_key_axn) do
        Class.new do
          include Axn

          def self.name = "GuardDupKey"

          exposes :rec
          def call = expose(rec: { id: 1, "id" => 2 })
        end
      end

      it "returns an error response instead of letting .call escape the exception" do
        response = described_class.perform(dup_key_axn, {}, text_content: :structured)

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
        expect(response.content.first[:text]).to eq("The tool could not produce a valid response")
      end

      it "reports the failure through axn's global on_exception hook (observability, not silent)" do
        captured = nil
        allow(Axn.config).to receive(:on_exception) { |e, **| captured = e }

        described_class.perform(dup_key_axn, {}, text_content: :structured)

        expect(captured).to be_a(Axn::Extensions::Serialization::UnserializableValue)
      end

      it "re-raises rather than swallowing when core's raises_in_dev? is on (bugs surface loudly)" do
        allow(Axn::Extensions).to receive(:raises_in_dev?).and_return(true)

        expect { described_class.perform(dup_key_axn, {}, text_content: :structured) }
          .to raise_error(Axn::Extensions::Serialization::UnserializableValue)
      end

      it "still returns an error response when the on_exception reporter itself raises" do
        allow(Axn.config).to receive(:on_exception).and_raise(RuntimeError, "reporter broken")

        response = described_class.perform(dup_key_axn, {}, text_content: :structured)

        expect(response.error?).to be true
      end

      it "guards ANY StandardError from the transport step, not only serialization" do
        allow(Axn::MCP::Serializer).to receive(:result_to_mcp_response).and_raise(RuntimeError, "boom")
        captured = nil
        allow(Axn.config).to receive(:on_exception) { |e, **| captured = e }

        response = described_class.perform(user_id_axn, {}, text_content: :structured)

        expect(response.error?).to be true
        expect(captured).to be_a(RuntimeError)
      end

      # The tool-facing response stays generic; this log line is an operator's only pointer to WHY. Mirrors
      # axn-openapi's dispatcher hint spec: named because reject_opaque_exposed_values is overridable, so a
      # hint naming only the gem-wide setter is a dead end whenever a per-tool override is what's in effect.
      describe "the opaque-rejection log hint" do
        # Set gem-wide rather than passed to `perform`: `reject_opaque_exposed_values` is no longer a
        # kwarg anywhere on this path -- `Axn::MCP.serialize_exposed` resolves it per-tool, and the hint
        # below re-resolves it the same way -- so config IS the only way to turn it on now.
        after { Axn::MCP.reset_config! }

        def captured_log_for(axn_class, reject_opaque_exposed_values:)
          Axn::MCP.config.reject_opaque_exposed_values = reject_opaque_exposed_values
          io = StringIO.new
          allow(Axn.config).to receive(:logger).and_return(Logger.new(io))
          described_class.perform(axn_class, {}, text_content: :structured)
          io.string
        end

        # Asserts against the specific ERROR line the guard writes, not the whole captured buffer: the
        # class also emits its own auto-log INFO lines (which correctly resolve a `.name` override
        # through `resolved_axn_name`), and asserting against the full buffer would pass even if the
        # hint itself renders the class as `#<Class:0x...>` -- exactly the interpolation bug this guards
        # against (Class#to_s does not dispatch through an overridden `.name`).
        it "names the offending tool and BOTH config levels when reject_opaque_exposed_values is on" do
          opaque_axn = Class.new do
            include Axn

            def self.name = "InvocationSpec::Opaque"

            exposes :thing
            def call = expose(thing: Object.new)
          end

          line = captured_log_for(opaque_axn, reject_opaque_exposed_values: true)
          hint_line = line.lines.find { |l| l.include?("[axn-mcp] failed to serialize") }

          expect(hint_line).to include("InvocationSpec::Opaque")
          expect(hint_line).to include("configure(:mcp)")
          expect(hint_line).to include("Axn::MCP.config.reject_opaque_exposed_values")
        end

        it "omits the hint when reject_opaque_exposed_values is off (the rejection can't be opaque-related)" do
          line = captured_log_for(dup_key_axn, reject_opaque_exposed_values: false)

          expect(line).to include("UnserializableValue")
          expect(line).not_to include("reject_opaque_exposed_values")
        end
      end
    end
  end
end
