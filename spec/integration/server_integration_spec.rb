# frozen_string_literal: true

require "json"

RSpec.describe "MCP Server Integration", type: :integration do
  let(:server) do
    MCP::Server.new(
      name: "test_server",
      version: "1.0.0",
      tools:,
      server_context:,
    )
  end

  let(:server_context) { { user_id: 42 } }

  def json_rpc_request(method, params = {}, id: 1)
    { jsonrpc: "2.0", id:, method:, params: }.to_json
  end

  def parse_response(json)
    JSON.parse(json, symbolize_names: true)
  end

  describe "tool registration" do
    let(:greet_tool) do
      Class.new(Axn::MCP::Tool) do
        def self.name
          "GreetTool"
        end

        description "Greet a user by name"
        expects :name, type: String, description: "The user's name"
        exposes :greeting, type: String, description: "The greeting message"

        def call
          expose greeting: "Hello, #{name}!"
        end
      end
    end

    let(:tools) { [greet_tool] }

    it "lists tools with auto-generated schemas" do
      response = parse_response(server.handle_json(json_rpc_request("tools/list")))

      expect(response[:result][:tools]).to be_an(Array)
      tool = response[:result][:tools].first

      expect(tool[:name]).to eq("greet_tool")
      expect(tool[:description]).to eq("Greet a user by name")

      input_schema = tool[:inputSchema]
      expect(input_schema[:properties][:name][:type]).to eq("string")
      expect(input_schema[:properties][:name][:description]).to eq("The user's name")
      expect(input_schema[:required]).to include("name")
      expect(input_schema[:properties]).not_to have_key(:server_context)

      output_schema = tool[:outputSchema]
      expect(output_schema[:properties][:greeting][:type]).to eq("string")
    end

    it "calls tool and returns structured response" do
      request = json_rpc_request("tools/call", { name: "greet_tool", arguments: { name: "Alice" } })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:isError]).to be_falsey
      expect(result[:content].first[:text]).to eq('{"greeting":"Hello, Alice!"}')
      expect(result[:structuredContent]).to eq({ greeting: "Hello, Alice!" })
    end
  end

  describe "server_context injection" do
    let(:context_tool) do
      Class.new(Axn::MCP::Tool) do
        def self.name
          "ContextTool"
        end

        description "Return server context info"
        exposes :user_id, type: Integer

        def call
          expose user_id: server_context[:user_id]
        end
      end
    end

    let(:tools) { [context_tool] }

    it "passes server_context to tool" do
      request = json_rpc_request("tools/call", { name: "context_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:structuredContent]).to eq({ user_id: 42 })
    end
  end

  describe "error handling" do
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

    let(:tools) { [failing_tool] }

    it "returns error response for failed actions" do
      request = json_rpc_request("tools/call", { name: "failing_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to eq("Something went wrong")
    end
  end

  describe "exception handling" do
    let(:exception_tool) do
      Class.new(Axn::MCP::Tool) do
        def self.name
          "ExceptionTool"
        end

        description "A tool that raises an exception"

        def call
          raise StandardError, "Unexpected error"
        end
      end
    end

    let(:tools) { [exception_tool] }

    it "returns error response for raised exceptions" do
      request = json_rpc_request("tools/call", { name: "exception_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to be_present
    end
  end

  describe "complex tool with multiple fields" do
    let(:create_user_tool) do
      Class.new(Axn::MCP::Tool) do
        def self.name
          "CreateUserTool"
        end

        description "Create a new user"
        read_only!

        expects :email, type: String, description: "User email"
        expects :role, inclusion: { in: %w[admin member guest] }, description: "User role"
        expects :age, type: Integer, optional: true, description: "User age"

        exposes :user_id, type: Integer
        exposes :status, type: String

        def call
          expose user_id: 123, status: "created"
        end
      end
    end

    let(:tools) { [create_user_tool] }

    it "lists tool with full schema including enums and optional fields" do
      response = parse_response(server.handle_json(json_rpc_request("tools/list")))
      tool = response[:result][:tools].first

      input_schema = tool[:inputSchema]
      expect(input_schema[:properties][:email][:type]).to eq("string")
      expect(input_schema[:properties][:role][:enum]).to eq(%w[admin member guest])
      expect(input_schema[:properties][:age][:type]).to eq("integer")
      expect(input_schema[:required]).to include("email", "role")
      expect(input_schema[:required]).not_to include("age")
    end

    it "includes annotations" do
      response = parse_response(server.handle_json(json_rpc_request("tools/list")))
      tool = response[:result][:tools].first

      annotations = tool[:annotations]
      expect(annotations[:readOnlyHint]).to be true
      expect(annotations[:destructiveHint]).to be false
    end

    it "calls tool and returns structured content" do
      request = json_rpc_request(
        "tools/call",
        { name: "create_user_tool", arguments: { email: "test@example.com", role: "admin" } },
      )
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:structuredContent]).to eq({ user_id: 123, status: "created" })
    end
  end

  describe "tool with custom success message" do
    let(:message_tool) do
      Class.new(Axn::MCP::Tool) do
        def self.name
          "MessageTool"
        end

        description "Tool with custom message"
        success "Operation completed!"

        def call
          # success
        end
      end
    end

    let(:tools) { [message_tool] }

    it "uses custom success message in response" do
      request = json_rpc_request("tools/call", { name: "message_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:content].first[:text]).to eq("Operation completed!")
    end
  end

  describe "mcp_text_content config and per-tool" do
    context "central config sets default to :message" do
      around do |example|
        original = Axn::MCP.config.mcp_text_content
        Axn::MCP.config.mcp_text_content = :message
        example.run
      ensure
        Axn::MCP.config.mcp_text_content = original
      end

      let(:structured_tool) do
        Class.new(Axn::MCP::Tool) do
          def self.name
            "StructuredTool"
          end

          description "Returns structured data"
          exposes :value, type: Integer
          success "Success message"

          def call
            expose value: 99
          end
        end
      end

      let(:tools) { [structured_tool] }

      it "uses success message in response when config is :message and tool has no override" do
        request = json_rpc_request("tools/call", { name: "structured_tool", arguments: {} })
        response = parse_response(server.handle_json(request))

        result = response[:result]
        expect(result[:content].first[:text]).to eq("Success message")
        expect(result[:structuredContent]).to eq({ value: 99 })
      end
    end

    context "per-tool overrides config" do
      around do |example|
        original = Axn::MCP.config.mcp_text_content
        Axn::MCP.config.mcp_text_content = :message
        example.run
      ensure
        Axn::MCP.config.mcp_text_content = original
      end

      let(:override_tool) do
        Class.new(Axn::MCP::Tool) do
          def self.name
            "OverrideTool"
          end

          mcp_text_content :structured
          description "Overrides to structured text"
          exposes :x, type: Integer
          success "Ignored"

          def call
            expose x: 1
          end
        end
      end

      let(:tools) { [override_tool] }

      it "per-tool :structured wins over config :message" do
        request = json_rpc_request("tools/call", { name: "override_tool", arguments: {} })
        response = parse_response(server.handle_json(request))

        result = response[:result]
        expect(result[:content].first[:text]).to eq('{"x":1}')
        expect(result[:structuredContent]).to eq({ x: 1 })
      end
    end
  end

  describe "factory-defined tool" do
    let(:factory_tool) do
      Axn::MCP::Tool.define(
        description: "Search for items",
        expects: { query: { type: String, description: "Search query" } },
        exposes: { count: { type: Integer } },
        annotations: { read_only_hint: true },
      ) do
        expose count: query.length
      end
    end

    let(:tools) { [factory_tool] }

    it "works with factory-defined tools" do
      response = parse_response(server.handle_json(json_rpc_request("tools/list")))
      tool = response[:result][:tools].first

      expect(tool[:inputSchema][:properties][:query][:type]).to eq("string")
      expect(tool[:annotations][:readOnlyHint]).to be true

      request = json_rpc_request("tools/call", { name: tool[:name], arguments: { query: "hello" } })
      call_response = parse_response(server.handle_json(request))

      expect(call_response[:result][:structuredContent]).to eq({ count: 5 })
    end

    it "supports mcp_text_content in define options" do
      message_tool = Axn::MCP::Tool.define(
        description: "Returns message",
        exposes: { value: { type: Integer } },
        mcp_text_content: :message,
      ) do
        expose value: 10
      end
      # When mcp_text_content is :message we use result.success; without success() DSL that may be default Axn message
      expect(message_tool.resolved_mcp_text_content).to eq(:message)
    end
  end
end
