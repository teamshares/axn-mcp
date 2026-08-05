# frozen_string_literal: true

RSpec.describe "Direct Axn Invocation", type: :integration do
  # PRO-2923: the retired dual-mode Axn::MCP::Tool base is gone. A tool is now authored once as a
  # plain Axn (always returns Axn::Result when called directly, with no MCP awareness), and
  # Axn::MCP.wrap produces a separate ::MCP::Tool whose .call always returns an MCP::Tool::Response.
  # These integration specs prove that author-once split end to end.

  describe "the original plain Axn, called directly (pure Axn, no MCP awareness)" do
    let(:greet_axn) do
      Class.new do
        include Axn

        def self.name = "GreetPlainly"

        description "Greet a user by name"
        expects :name, type: String
        expects :user_id, on: :ambient_context, type: Object, optional: true # spread from server_context
        exposes :greeting, type: String

        def call
          expose greeting: "Hello, #{name}! (user #{user_id.inspect})"
        end
      end
    end

    describe "success case" do
      it "returns an ok Axn::Result via .call" do
        result = greet_axn.call(name: "Alice")

        expect(result).to be_a(Axn::Result)
        expect(result).to be_ok
        expect(result.greeting).to eq("Hello, Alice! (user nil)")
      end

      it "returns an ok Axn::Result via .call! (never an MCP::Tool::Response)" do
        result = greet_axn.call!(name: "Bob")

        expect(result).to be_a(Axn::Result)
        expect(result).to be_ok
        expect(result.greeting).to eq("Hello, Bob! (user nil)")
      end

      it "has a nil server_context when called directly with none provided (no ambient leakage)" do
        result = greet_axn.call(name: "Carol")

        expect(result).to be_ok
        # The interpolated "(user nil)" proves the ambient user_id resolved to nil:
        # the direct-call path picks up no ambient Current state.
        expect(result.greeting).to eq("Hello, Carol! (user nil)")
      end
    end

    describe "failure case with fail!(reason)" do
      let(:failing_axn) do
        Class.new do
          include Axn

          def self.name = "FailingPlainly"

          description "A tool that fails"

          def call
            fail! "email taken"
          end
        end
      end

      it "returns a failed Axn::Result via .call, exposing the bare reason (no headline prefix)" do
        result = failing_axn.call

        expect(result).to be_a(Axn::Result)
        expect(result).not_to be_ok
        expect(result.exception).to be_a(Axn::Failure)
        expect(result.message).to eq("email taken")
      end

      it "raises Axn::Failure via .call! whose message is the bare reason" do
        expect { failing_axn.call! }.to raise_error(Axn::Failure, "email taken")
      end
    end

    describe "failure case with a bare fail!" do
      let(:bare_fail_axn) do
        Class.new do
          include Axn

          def self.name = "BareFailPlainly"

          def call
            fail!
          end
        end
      end

      it "returns a failed Axn::Result via .call with the generic message" do
        result = bare_fail_axn.call

        expect(result).not_to be_ok
        expect(result.exception).to be_a(Axn::Failure)
        expect(result.message).to eq("Something went wrong")
      end
    end

    describe "failure case with a raised exception" do
      let(:exception_axn) do
        Class.new do
          include Axn

          def self.name = "ExceptionPlainly"

          description "A tool that raises"

          def call
            raise StandardError, "Unexpected error"
          end
        end
      end

      it "returns a failed Axn::Result via .call, surfacing the generic message but preserving the exception" do
        result = exception_axn.call

        expect(result).to be_a(Axn::Result)
        expect(result).not_to be_ok
        expect(result.exception).to be_a(StandardError)
        expect(result.exception.message).to eq("Unexpected error")
        expect(result.message).to eq("Something went wrong")
      end

      it "re-raises the exception via .call!" do
        expect { exception_axn.call! }.to raise_error(StandardError, "Unexpected error")
      end
    end

    describe "input validation" do
      let(:validated_axn) do
        Class.new do
          include Axn

          def self.name = "ValidatedPlainly"

          expects :email, type: String
          expects :age, type: Integer

          def call
            # success
          end
        end
      end

      it "fails when a required field is missing" do
        result = validated_axn.call(email: "test@example.com")

        expect(result).not_to be_ok
      end

      it "succeeds when all required fields are provided" do
        result = validated_axn.call(email: "test@example.com", age: 25)

        expect(result).to be_ok
      end
    end

    describe "exposed data access" do
      let(:data_axn) do
        Class.new do
          include Axn

          def self.name = "DataPlainly"

          exposes :count, type: Integer
          exposes :items, type: Array

          def call
            expose count: 3, items: %w[a b c]
          end
        end
      end

      it "provides access to exposed data via result methods" do
        result = data_axn.call

        expect(result.count).to eq(3)
        expect(result.items).to eq(%w[a b c])
      end

      it "exposes multiple fields correctly" do
        result = data_axn.call

        expect(result).to be_ok
        expect(result.count).to be_a(Integer)
        expect(result.items).to be_an(Array)
        expect(result.items.length).to eq(3)
      end
    end
  end

  describe "the Axn::MCP.wrap-generated tool, called with server_context:" do
    let(:double_axn) do
      Class.new do
        include Axn

        def self.name = "DoubleValuePlainly"

        expects :value, type: Integer
        exposes :doubled, type: Integer

        def call
          expose doubled: value * 2
        end
      end
    end

    let(:wrapped_tool) { Axn::MCP.wrap(double_axn, description: "Doubles a value", name: "double_value_plainly") }

    it "is a separate ::MCP::Tool subclass, distinct from the plain Axn" do
      expect(wrapped_tool).to be < MCP::Tool
      expect(wrapped_tool).not_to eq(double_axn)
    end

    it "returns an MCP::Tool::Response (never a raw Axn::Result) when called with server_context:" do
      response = wrapped_tool.call(value: 21, server_context: { user_id: 1 })

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.structured_content).to eq({ "doubled" => 42 })
    end

    it "spreads server_context: into the wrapped Axn's ambient_context (declared fields resolve from it)" do
      context_axn = Class.new do
        include Axn

        def self.name = "EchoContextPlainly"

        expects :user_id, on: :ambient_context, type: Object, optional: true # spread from server_context
        exposes :seen_user, type: Integer

        def call
          expose seen_user: user_id
        end
      end

      tool = Axn::MCP.wrap(context_axn, description: "Echoes the server-context user")
      response = tool.call(server_context: { user_id: 42 })

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.structured_content).to eq({ "seen_user" => 42 })
    end
  end

  describe "Axn::MCP.wrap through a real MCP::Server (author once, expose over MCP transport)" do
    let(:plain_axn) do
      Class.new do
        include Axn

        def self.name = "DoubleValuePlainly"

        expects :value, type: Integer
        expects :user_id, on: :ambient_context, type: Object, optional: true # spread from server_context; excluded from inputSchema
        exposes :doubled, type: Integer

        def call
          expose doubled: value * 2
        end
      end
    end

    let(:wrapped_tool) { Axn::MCP.wrap(plain_axn, description: "Doubles a value", name: "double_value_plainly") }

    it "lists the wrapped tool's schema via tools/list" do
      server = MCP::Server.new(
        name: "test",
        version: "1.0.0",
        tools: [wrapped_tool],
        server_context: { user_id: 1 },
      )

      request = { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json
      response = JSON.parse(server.handle_json(request), symbolize_names: true)

      tool_description = response[:result][:tools].first
      expect(tool_description[:name]).to eq("double_value_plainly")
      expect(tool_description[:inputSchema][:properties]).to have_key(:value)
      expect(tool_description[:inputSchema][:properties]).not_to have_key(:user_id) # ambient fields excluded
    end

    it "round-trips a tools/call, proving the original plain Axn is exposed over real MCP transport" do
      server = MCP::Server.new(
        name: "test",
        version: "1.0.0",
        tools: [wrapped_tool],
        server_context: { user_id: 1 },
      )

      request = { jsonrpc: "2.0", id: 1, method: "tools/call",
                  params: { name: "double_value_plainly", arguments: { value: 21 } } }.to_json
      response = JSON.parse(server.handle_json(request), symbolize_names: true)

      expect(response[:result][:structuredContent]).to eq({ doubled: 42 })
    end
  end
end
