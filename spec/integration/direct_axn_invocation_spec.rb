# frozen_string_literal: true

RSpec.describe "Direct Axn Invocation", type: :integration do
  describe "calling tool without server_context (direct Axn mode)" do
    let(:greet_tool) do
      Class.new(Axn::MCP::Tool) do
        def self.name
          "GreetTool"
        end

        description "Greet a user by name"
        expects :name, type: String
        exposes :greeting, type: String

        def call
          expose greeting: "Hello, #{name}!"
        end
      end
    end

    describe "success case" do
      it "returns Axn::Result when called via .call" do
        result = greet_tool.call(name: "Alice")

        expect(result).to be_a(Axn::Result)
        expect(result).to be_ok
        expect(result.greeting).to eq("Hello, Alice!")
      end

      it "returns Axn::Result when called via .call!" do
        result = greet_tool.call!(name: "Bob")

        expect(result).to be_a(Axn::Result)
        expect(result).to be_ok
        expect(result.greeting).to eq("Hello, Bob!")
      end

      it "has nil server_context when not provided" do
        received_context = nil
        tool = Class.new(Axn::MCP::Tool) do
          def self.name
            "ContextCheckTool"
          end

          define_method(:call) do
            received_context = server_context
          end
        end

        tool.call
        expect(received_context).to be_nil
      end
    end

    describe "failure case with fail!" do
      let(:failing_tool) do
        Class.new(Axn::MCP::Tool) do
          def self.name
            "FailingTool"
          end

          description "A tool that fails"

          def call
            fail! "Something went wrong"
          end
        end
      end

      it "returns failed Axn::Result via .call" do
        result = failing_tool.call

        expect(result).to be_a(Axn::Result)
        expect(result).not_to be_ok
        expect(result.exception).to be_a(Axn::Failure)
        expect(result.message).to eq("Something went wrong")
      end

      it "raises Axn::Failure via .call!" do
        expect { failing_tool.call! }.to raise_error(Axn::Failure, "Something went wrong")
      end
    end

    describe "failure case with exception" do
      let(:exception_tool) do
        Class.new(Axn::MCP::Tool) do
          def self.name
            "ExceptionTool"
          end

          description "A tool that raises"

          def call
            raise StandardError, "Unexpected error"
          end
        end
      end

      it "returns failed Axn::Result via .call" do
        result = exception_tool.call

        expect(result).to be_a(Axn::Result)
        expect(result).not_to be_ok
        expect(result.exception).to be_a(StandardError)
        expect(result.exception.message).to eq("Unexpected error")
      end

      it "raises the exception via .call!" do
        expect { exception_tool.call! }.to raise_error(StandardError, "Unexpected error")
      end
    end

    describe "input validation" do
      let(:validated_tool) do
        Class.new(Axn::MCP::Tool) do
          def self.name
            "ValidatedTool"
          end

          expects :email, type: String
          expects :age, type: Integer

          def call
            # success
          end
        end
      end

      it "fails with validation error when required field is missing" do
        result = validated_tool.call(email: "test@example.com")

        expect(result).not_to be_ok
      end

      it "succeeds when all required fields are provided" do
        result = validated_tool.call(email: "test@example.com", age: 25)

        expect(result).to be_ok
      end
    end

    describe "exposed data access" do
      let(:data_tool) do
        Class.new(Axn::MCP::Tool) do
          def self.name
            "DataTool"
          end

          exposes :count, type: Integer
          exposes :items, type: Array

          def call
            expose count: 3, items: %w[a b c]
          end
        end
      end

      it "provides access to exposed data via result methods" do
        result = data_tool.call

        expect(result.count).to eq(3)
        expect(result.items).to eq(%w[a b c])
      end

      it "exposes multiple fields correctly" do
        result = data_tool.call

        expect(result).to be_ok
        expect(result.count).to be_a(Integer)
        expect(result.items).to be_an(Array)
        expect(result.items.length).to eq(3)
      end
    end

    describe "dual-use pattern" do
      let(:dual_use_tool) do
        Class.new(Axn::MCP::Tool) do
          def self.name
            "DualUseTool"
          end

          description "Tool that works both as MCP tool and direct Axn"
          expects :value, type: Integer
          exposes :doubled, type: Integer

          def call
            expose doubled: value * 2
          end
        end
      end

      it "returns MCP::Tool::Response when server_context is provided" do
        response = dual_use_tool.call(value: 21, server_context: { user_id: 1 })

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.structured_content).to eq({ "doubled" => 42 })
      end

      it "returns Axn::Result when server_context is absent" do
        result = dual_use_tool.call(value: 21)

        expect(result).to be_a(Axn::Result)
        expect(result).to be_ok
        expect(result.doubled).to eq(42)
      end

      it "works via MCP server (server injects server_context)" do
        server = MCP::Server.new(
          name: "test",
          version: "1.0.0",
          tools: [dual_use_tool],
          server_context: { user_id: 1 },
        )

        request = { jsonrpc: "2.0", id: 1, method: "tools/call",
                    params: { name: "dual_use_tool", arguments: { value: 21 } } }.to_json
        response = JSON.parse(server.handle_json(request), symbolize_names: true)

        expect(response[:result][:structuredContent]).to eq({ doubled: 42 })
      end
    end
  end
end
