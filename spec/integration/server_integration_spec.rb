# frozen_string_literal: true

require "json"

# Defined at top-level so it is accessible across describe blocks without
# triggering Lint/ConstantDefinitionInBlock.
IntegrationRecord = Data.define(:source, :provider_name, :active, :status)

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

  # A raise that happens mid-serialization (after the Axn ran) is caught by MCP::Server, but the
  # SUPPORTED mcp range surfaces it two ways: a top-level JSON-RPC error object (mcp >= ~1.0) or a
  # tool result with `isError: true` (older). Both satisfy the invariant these specs care about —
  # the raise is caught and surfaced, never escaped and never dropped as a clean success. Assert the
  # invariant, not one version's shape.
  def surfaced_failure?(response)
    response.key?(:error) || response.dig(:result, :isError) == true
  end

  def surfaced_error_text(response)
    response.dig(:error, :data) || response.dig(:error, :message) || response.dig(:result, :content, 0, :text)
  end

  describe "tool registration" do
    let(:greet_axn) do
      Class.new do
        include Axn

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

    let(:tools) { [Axn::MCP.wrap(greet_axn)] }

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
    let(:context_axn) do
      Class.new do
        include Axn

        def self.name
          "ContextTool"
        end

        description "Return server context info"
        expects :user_id, on: :ambient_context, type: Object, optional: true # spread from server_context
        exposes :seen_user_id, type: Integer, optional: true

        def call
          expose seen_user_id: user_id
        end
      end
    end

    let(:tools) { [Axn::MCP.wrap(context_axn)] }

    it "passes server_context to tool" do
      request = json_rpc_request("tools/call", { name: "context_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:structuredContent]).to eq({ seen_user_id: 42 })
    end
  end

  describe "error handling" do
    let(:failing_axn) do
      Class.new do
        include Axn

        def self.name
          "FailingTool"
        end

        description "A tool that fails"

        def call
          fail! "email taken"
        end
      end
    end

    let(:tools) { [Axn::MCP.wrap(failing_axn)] }

    it "returns error response surfacing the raw result.error for an explicit fail! reason" do
      request = json_rpc_request("tools/call", { name: "failing_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to eq("email taken")
    end
  end

  describe "error handling for a bare fail!" do
    let(:bare_failing_axn) do
      Class.new do
        include Axn

        def self.name
          "BareFailingTool"
        end

        description "A tool that fails without a reason"

        def call
          fail!
        end
      end
    end

    let(:tools) { [Axn::MCP.wrap(bare_failing_axn)] }

    it "surfaces axn's default failure message" do
      request = json_rpc_request("tools/call", { name: "bare_failing_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to eq("Something went wrong")
    end
  end

  describe "exception handling" do
    let(:exception_axn) do
      Class.new do
        include Axn

        def self.name
          "ExceptionTool"
        end

        description "A tool that raises an exception"

        def call
          raise StandardError, "Unexpected error"
        end
      end
    end

    let(:tools) { [Axn::MCP.wrap(exception_axn)] }

    it "returns error response for raised exceptions with axn's default message" do
      request = json_rpc_request("tools/call", { name: "exception_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to eq("Something went wrong")
    end
  end

  describe "unserializable exposed value" do
    # axn #206 (PRO-2988): serialization now RAISES (Axn::Extensions::Serialization::UnserializableValue, an
    # ArgumentError) rather than emitting a lossy/malformed body — here two Hash keys (:id and
    # "id") stringify to the same JSON property and would silently collapse. Unlike an exception
    # *inside* #call (which axn catches into a failed Result — see "exception handling" above), this
    # raise happens during serialization *after* the Axn ran, outside axn's rescue, so it propagates
    # to MCP::Server, which converts it into a JSON-RPC internal error. The point of this spec: the
    # raise surfaces as the transport's error shape, not an escaped exception and not a dropped value.
    let(:unserializable_axn) do
      Class.new do
        include Axn

        def self.name
          "DupKeyTool"
        end

        description "Exposes a Hash whose keys collide as one JSON property"
        exposes :rec

        def call = expose(rec: { id: 1, "id" => 2 })
      end
    end

    let(:tools) { [Axn::MCP.wrap(unserializable_axn)] }

    it "surfaces the raise as an error (either mcp shape), never an escape or a lossy success" do
      request = json_rpc_request("tools/call", { name: "dup_key_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      expect(surfaced_failure?(response)).to be(true) # not a silently-lossy success result
      expect(surfaced_error_text(response).to_s).to include("dup_key_tool")
    end
  end

  describe "exposed value nested deeper than JSON's max_nesting" do
    # axn #206 draws a line: serialization guarantees encodable *values*, but deliberately does
    # NOT own nesting depth — max_nesting (100 by default) is the encoder's option, not core's. So a
    # >100-deep (otherwise fine) structure passes serialization and then makes JSON.generate raise
    # JSON::NestingError. We keep no local rescue around JSON.generate; MCP::Server's own rescue maps
    # it to the same JSON-RPC error shape, so it still degrades gracefully instead of escaping.
    let(:deep_axn) do
      Class.new do
        include Axn

        def self.name
          "DeepTool"
        end

        description "Exposes a structure nested past JSON's default max_nesting"
        exposes :rec

        def call
          root = {}
          node = root
          200.times do
            node["n"] = {}
            node = node["n"]
          end
          expose(rec: root)
        end
      end
    end

    let(:tools) { [Axn::MCP.wrap(deep_axn)] }

    it "surfaces the encode failure as an error (either mcp shape) rather than escaping (max_nesting is the encoder's, not core's)" do
      request = json_rpc_request("tools/call", { name: "deep_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      expect(surfaced_failure?(response)).to be(true)
    end
  end

  describe "complex tool with multiple fields" do
    let(:create_user_axn) do
      Class.new do
        include Axn

        def self.name
          "CreateUserTool"
        end

        description "Create a new user"
        semantic_hints :read_only

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

    let(:tools) { [Axn::MCP.wrap(create_user_axn)] }

    it "lists tool with full schema including enums and optional fields" do
      response = parse_response(server.handle_json(json_rpc_request("tools/list")))
      tool = response[:result][:tools].first

      input_schema = tool[:inputSchema]
      expect(input_schema[:properties][:email][:type]).to eq("string")
      expect(input_schema[:properties][:role][:enum]).to eq(%w[admin member guest])
      # Nullable (optional:) fields reflect as a type array, not a bare type -- axn core's documented
      # input_schema nullability behavior.
      expect(input_schema[:properties][:age][:type]).to eq(%w[integer null])
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
    let(:message_axn) do
      Class.new do
        include Axn

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

    let(:tools) { [Axn::MCP.wrap(message_axn)] }

    it "uses custom success message in response" do
      request = json_rpc_request("tools/call", { name: "message_tool", arguments: {} })
      response = parse_response(server.handle_json(request))

      result = response[:result]
      expect(result[:content].first[:text]).to eq("Operation completed!")
    end
  end

  describe "present_as config and per-tool" do
    context "central config sets default to :message" do
      around do |example|
        original = Axn::MCP.config.present_as
        Axn::MCP.config.present_as = :message
        example.run
      ensure
        Axn::MCP.config.present_as = original
      end

      let(:structured_axn) do
        Class.new do
          include Axn

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

      let(:tools) { [Axn::MCP.wrap(structured_axn)] }

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
        original = Axn::MCP.config.present_as
        Axn::MCP.config.present_as = :message
        example.run
      ensure
        Axn::MCP.config.present_as = original
      end

      let(:override_axn) do
        Class.new do
          include Axn

          def self.name
            "OverrideTool"
          end

          description "Overrides to structured text"
          exposes :x, type: Integer
          success "Ignored"

          def call
            expose x: 1
          end
        end
      end

      # wrap's own present_as: kwarg is the most-local per-tool override and wins over the
      # gem-wide config default of :message.
      let(:tools) { [Axn::MCP.wrap(override_axn, present_as: :structured)] }

      it "per-tool :structured wins over config :message" do
        request = json_rpc_request("tools/call", { name: "override_tool", arguments: {} })
        response = parse_response(server.handle_json(request))

        result = response[:result]
        expect(result[:content].first[:text]).to eq('{"x":1}')
        expect(result[:structuredContent]).to eq({ x: 1 })
      end
    end
  end

  describe "factory-built tool wrapped via Axn::MCP.wrap" do
    let(:factory_axn) do
      Axn::Factory.build(
        expects: { query: { type: String, description: "Search query" } },
        exposes: { count: { type: Integer } },
      ) do
        expose count: query.length
      end
    end

    let(:factory_tool) do
      Axn::MCP.wrap(
        factory_axn,
        name: "search",
        description: "Search for items",
        annotations: { read_only_hint: true },
      )
    end

    let(:tools) { [factory_tool] }

    it "works end-to-end with factory-built, wrapped tools" do
      response = parse_response(server.handle_json(json_rpc_request("tools/list")))
      tool = response[:result][:tools].first

      expect(tool[:inputSchema][:properties][:query][:type]).to eq("string")
      expect(tool[:annotations][:readOnlyHint]).to be true

      request = json_rpc_request("tools/call", { name: tool[:name], arguments: { query: "hello" } })
      call_response = parse_response(server.handle_json(request))

      expect(call_response[:result][:structuredContent]).to eq({ count: 5 })
    end

    it "honors present_as passed to wrap" do
      message_axn = Axn::Factory.build(
        exposes: { value: { type: Integer } },
        success: "Returned message",
      ) do
        expose value: 10
      end
      message_tool = Axn::MCP.wrap(
        message_axn,
        name: "message_returner",
        description: "Returns message",
        present_as: :message,
      )

      response = message_tool.call(value: 10, server_context: {})

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.content.first[:text]).to eq("Returned message")
    end
  end

  describe "of:/shape: items schema — end-to-end" do
    let(:list_axn) do
      Class.new do
        include Axn

        def self.name
          "ListIntegrationsTool"
        end

        description "List company integrations"

        exposes :integrations, type: Array, of: IntegrationRecord do
          field :source, type: String
          field :status, type: String, inclusion: { in: %w[connected error needs_reconnect] }
          field :active, type: :boolean, optional: true
        end

        def call
          expose integrations: []
        end
      end
    end

    let(:list_tool) { Axn::MCP.wrap(list_axn) }

    it "emits items in output_schema" do
      items = list_tool.output_schema.to_h[:properties][:integrations][:items]
      expect(items[:type]).to eq("object")
    end

    it "includes typed member properties in items" do
      items = list_tool.output_schema.to_h[:properties][:integrations][:items]
      expect(items[:properties][:source][:type]).to eq("string")
    end

    it "includes enum from inclusion: in items.properties" do
      items = list_tool.output_schema.to_h[:properties][:integrations][:items]
      expect(items[:properties][:status][:enum]).to eq(%w[connected error needs_reconnect])
    end

    it "preserves bare {} for unannotated Data members" do
      items = list_tool.output_schema.to_h[:properties][:integrations][:items]
      expect(items[:properties][:provider_name]).to eq({})
    end

    it "derives required from required members (optional: true excluded)" do
      items = list_tool.output_schema.to_h[:properties][:integrations][:items]
      expect(items[:required]).to include("source", "status")
      expect(items[:required]).not_to include("active")
    end

    it "surfaces items through Tool.to_h outputSchema" do
      tool_hash = list_tool.to_h
      items = tool_hash[:outputSchema][:properties][:integrations][:items]
      expect(items[:type]).to eq("object")
      expect(items[:properties][:status][:enum]).to eq(%w[connected error needs_reconnect])
    end
  end
end
