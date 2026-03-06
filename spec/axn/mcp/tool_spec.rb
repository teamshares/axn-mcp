# frozen_string_literal: true

RSpec.describe Axn::MCP::Tool do
  let(:server_context) { { user_id: 1 } }

  describe ".call with server_context (MCP mode)" do
    describe "success response" do
      it "returns MCP::Tool::Response with text content" do
        tool = Class.new(described_class) do
          expects :name, type: String

          def call
            # no-op, success
          end
        end

        response = tool.call(name: "Alice", server_context:)
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
        expect(response.content.first[:text]).to include("completed successfully")
      end

      it "uses result.message for text content" do
        tool = Class.new(described_class) do
          expects :name, type: String
          success "Hello, world!"

          def call
            # no-op
          end
        end

        response = tool.call(name: "Alice", server_context:)
        expect(response.content.first[:text]).to eq("Hello, world!")
      end

      it "includes exposed data in structured_content" do
        tool = Class.new(described_class) do
          expects :name, type: String
          exposes :greeting, type: String

          def call
            expose greeting: "Hello, #{name}!"
          end
        end

        response = tool.call(name: "Alice", server_context:)
        expect(response.structured_content).to eq({ "greeting" => "Hello, Alice!" })
      end

      it "uses JSON of structured content for text when tool has exposes (default :structured)" do
        tool = Class.new(described_class) do
          expects :name, type: String
          exposes :greeting, type: String

          def call
            expose greeting: "Hello, #{name}!"
          end
        end

        response = tool.call(name: "Alice", server_context:)
        expect(response.content.first[:text]).to eq('{"greeting":"Hello, Alice!"}')
      end

      it "uses result.success for text when mcp_text_content :message" do
        tool = Class.new(described_class) do
          mcp_text_content :message
          exposes :greeting, type: String
          success "Custom success message"

          def call
            expose greeting: "Hello!"
          end
        end

        response = tool.call(server_context:)
        expect(response.content.first[:text]).to eq("Custom success message")
        expect(response.structured_content).to eq({ "greeting" => "Hello!" })
      end

      it "serializes complex objects in structured_content" do
        tool = Class.new(described_class) do
          exposes :data, type: Hash

          def call
            expose data: { nested: { value: 42 }, list: [1, 2, 3] }
          end
        end

        response = tool.call(server_context:)
        expect(response.structured_content["data"]).to eq({
                                                            "nested" => { "value" => 42 },
                                                            "list" => [1, 2, 3],
                                                          })
      end
    end

    describe "error response" do
      it "returns error response when action fails" do
        tool = Class.new(described_class) do
          def call
            fail! "Something went wrong"
          end
        end

        response = tool.call(server_context:)
        expect(response.error?).to be true
        expect(response.content.first[:text]).to eq("Something went wrong")
      end

      it "uses default error message when none provided" do
        tool = Class.new(described_class) do
          def call
            fail!
          end
        end

        response = tool.call(server_context:)
        expect(response.error?).to be true
        expect(response.content.first[:text]).to be_present
      end
    end

    describe "server_context access" do
      it "passes server_context to action" do
        received_context = nil
        tool = Class.new(described_class) do
          define_method(:call) do
            received_context = server_context
          end
        end

        tool.call(server_context: { user_id: 123 })
        expect(received_context).to eq({ user_id: 123 })
      end

      it "does not include server_context in input schema" do
        tool = Class.new(described_class) do
          expects :name, type: String
        end

        schema = tool.input_schema.to_h
        expect(schema[:properties]).to have_key(:name)
        expect(schema[:properties]).not_to have_key(:server_context)
      end
    end

    describe "argument handling" do
      it "accepts keyword arguments" do
        received_name = nil
        tool = Class.new(described_class) do
          expects :name, type: String

          define_method(:call) do
            received_name = name
          end
        end

        tool.call(name: "Alice", server_context:)
        expect(received_name).to eq("Alice")
      end
    end
  end

  describe ".call without server_context (direct Axn mode)" do
    it "returns Axn::Result on success" do
      tool = Class.new(described_class) do
        exposes :greeting, type: String

        def call
          expose greeting: "Hello!"
        end
      end

      result = tool.call
      expect(result).to be_a(Axn::Result)
      expect(result).to be_ok
      expect(result.greeting).to eq("Hello!")
    end

    it "returns failed Axn::Result on fail!" do
      tool = Class.new(described_class) do
        def call
          fail! "Something went wrong"
        end
      end

      result = tool.call
      expect(result).to be_a(Axn::Result)
      expect(result).not_to be_ok
      expect(result.message).to eq("Something went wrong")
    end

    it "returns failed Axn::Result on exception" do
      tool = Class.new(described_class) do
        def call
          raise StandardError, "Unexpected"
        end
      end

      result = tool.call
      expect(result).to be_a(Axn::Result)
      expect(result).not_to be_ok
      expect(result.exception).to be_a(StandardError)
    end

    it "has nil server_context" do
      received_context = :not_called
      tool = Class.new(described_class) do
        define_method(:call) do
          received_context = server_context
        end
      end

      tool.call
      expect(received_context).to be_nil
    end
  end

  describe ".call!" do
    context "with server_context (MCP mode)" do
      it "returns MCP::Tool::Response on success" do
        tool = Class.new(described_class) do
          exposes :value, type: Integer

          def call
            expose value: 42
          end
        end

        response = tool.call!(server_context: { user_id: 1 })
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end

      it "returns MCP::Tool::Response with error on failure" do
        tool = Class.new(described_class) do
          def call
            fail! "Failed"
          end
        end

        response = tool.call!(server_context: { user_id: 1 })
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end
    end

    context "without server_context (direct Axn mode)" do
      it "returns Axn::Result on success" do
        tool = Class.new(described_class) do
          exposes :value, type: Integer

          def call
            expose value: 42
          end
        end

        result = tool.call!
        expect(result).to be_a(Axn::Result)
        expect(result).to be_ok
        expect(result.value).to eq(42)
      end

      it "raises Axn::Failure on fail!" do
        tool = Class.new(described_class) do
          def call
            fail! "Controlled failure"
          end
        end

        expect { tool.call! }.to raise_error(Axn::Failure, "Controlled failure")
      end

      it "raises the original exception on error" do
        tool = Class.new(described_class) do
          def call
            raise ArgumentError, "Bad argument"
          end
        end

        expect { tool.call! }.to raise_error(ArgumentError, "Bad argument")
      end
    end
  end

  describe ".input_schema" do
    it "returns auto-generated InputSchema" do
      tool = Class.new(described_class) do
        expects :name, type: String, description: "User name"
        expects :age, type: Integer, optional: true
      end

      schema = tool.input_schema
      expect(schema).to be_a(MCP::Tool::InputSchema)
      expect(schema.to_h[:properties][:name][:type]).to eq("string")
      expect(schema.to_h[:properties][:name][:description]).to eq("User name")
      expect(schema.to_h[:required]).to include("name")
      expect(schema.to_h[:required]).not_to include("age")
    end

    it "allows manual override" do
      tool = Class.new(described_class) do
        input_schema({ properties: { custom: { type: "string" } } })
      end

      schema = tool.input_schema
      expect(schema.to_h[:properties]).to have_key(:custom)
    end
  end

  describe ".output_schema" do
    it "returns auto-generated OutputSchema" do
      tool = Class.new(described_class) do
        exposes :output, type: String, description: "The output"
      end

      schema = tool.output_schema
      expect(schema).to be_a(MCP::Tool::OutputSchema)
      expect(schema.to_h[:properties][:output][:type]).to eq("string")
    end

    it "returns nil when no exposes" do
      tool = Class.new(described_class) do
        expects :name, type: String
      end

      expect(tool.output_schema).to be_nil
    end
  end

  describe ".to_h" do
    it "includes auto-generated schemas in MCP format" do
      tool = Class.new(described_class) do
        description "A test tool"
        expects :name, type: String
        exposes :greeting, type: String

        def self.name
          "TestTool"
        end
      end

      hash = tool.to_h
      expect(hash[:description]).to eq("A test tool")
      expect(hash[:inputSchema]).to be_a(Hash)
      expect(hash[:inputSchema][:properties][:name][:type]).to eq("string")
      expect(hash[:outputSchema][:properties][:greeting][:type]).to eq("string")
    end
  end

  describe "annotation shortcuts" do
    # MCP Tool Annotations: https://github.com/modelcontextprotocol/ruby-sdk#tool-annotations
    # - destructive_hint: Indicates if tool performs destructive operations (default: true)
    # - idempotent_hint: Indicates if tool's operations are idempotent (default: false)
    # - open_world_hint: Indicates if tool operates in open world context (default: true)
    # - read_only_hint: Indicates if tool only reads data (default: false)
    # - title: Human-readable title for the tool

    describe ".read_only!" do
      it "sets read_only_hint true and destructive_hint false" do
        tool = Class.new(described_class) do
          read_only!
        end

        expect(tool.annotations_value.read_only_hint).to be true
        expect(tool.annotations_value.destructive_hint).to be false
      end
    end

    describe ".destructive!" do
      it "sets destructive_hint true and read_only_hint false" do
        tool = Class.new(described_class) do
          destructive!
        end

        expect(tool.annotations_value.destructive_hint).to be true
        expect(tool.annotations_value.read_only_hint).to be false
      end
    end

    describe ".idempotent!" do
      it "sets idempotent_hint true" do
        tool = Class.new(described_class) do
          idempotent!
        end

        expect(tool.annotations_value.idempotent_hint).to be true
      end
    end

    describe ".open_world!" do
      it "sets open_world_hint true" do
        tool = Class.new(described_class) do
          open_world!
        end

        expect(tool.annotations_value.open_world_hint).to be true
      end
    end

    describe ".closed_world!" do
      it "sets open_world_hint false" do
        tool = Class.new(described_class) do
          closed_world!
        end

        expect(tool.annotations_value.open_world_hint).to be false
      end
    end

    describe "using annotations directly" do
      it "supports all MCP annotation options" do
        tool = Class.new(described_class) do
          annotations(
            destructive_hint: false,
            idempotent_hint: true,
            open_world_hint: false,
            read_only_hint: true,
            title: "My Custom Tool Title",
          )
        end

        expect(tool.annotations_value.destructive_hint).to be false
        expect(tool.annotations_value.idempotent_hint).to be true
        expect(tool.annotations_value.open_world_hint).to be false
        expect(tool.annotations_value.read_only_hint).to be true
        expect(tool.annotations_value.title).to eq("My Custom Tool Title")
      end
    end
  end

  describe ".define" do
    it "creates a tool class with expects/exposes" do
      tool = described_class.define(
        description: "Greet a user",
        expects: [:name],
        exposes: [:greeting],
      ) do
        expose greeting: "Hello, #{name}!"
      end

      expect(tool.description_value).to eq("Greet a user")
      response = tool.call(name: "Alice", server_context:)
      expect(response.structured_content["greeting"]).to eq("Hello, Alice!")
    end

    it "accepts hash-style field declarations" do
      tool = described_class.define(
        description: "Test tool",
        expects: { name: { type: String } },
        exposes: { output: { type: String } },
      ) do
        expose output: name.upcase
      end

      schema = tool.input_schema
      expect(schema.to_h[:properties][:name][:type]).to eq("string")
    end

    it "applies annotations when provided" do
      tool = described_class.define(
        description: "Read-only tool",
        annotations: { read_only_hint: true },
      ) do
        # no-op
      end

      expect(tool.annotations_value.read_only_hint).to be true
    end

    it "works without a block" do
      tool = described_class.define(
        description: "No-op tool",
        expects: [:name],
      )

      response = tool.call(name: "test", server_context:)
      expect(response.error?).to be false
    end

    it "accepts mixed array of symbols and hashes in expects" do
      tool = described_class.define(
        description: "Mixed expects",
        expects: [:name, { age: { type: Integer } }],
      ) do
        # no-op
      end

      schema = tool.input_schema.to_h
      expect(schema[:properties]).to have_key(:name)
      expect(schema[:properties][:age][:type]).to eq("integer")
    end
  end

  describe "mcp_text_content" do
    it "raises ArgumentError for invalid value" do
      expect do
        Class.new(described_class) do
          mcp_text_content :invalid

          def call
            # no-op
          end
        end
      end.to raise_error(ArgumentError, /mcp_text_content must be one of/)
    end

    context "central config" do
      around do |example|
        original = Axn::MCP.config.mcp_text_content
        Axn::MCP.config.mcp_text_content = :message
        example.run
      ensure
        Axn::MCP.config.mcp_text_content = original
      end

      it "uses config default when tool does not set mcp_text_content" do
        tool = Class.new(described_class) do
          exposes :greeting, type: String
          success "Tool message"

          def call
            expose greeting: "Hi"
          end
        end

        response = tool.call(server_context:)
        expect(response.content.first[:text]).to eq("Tool message")
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

      it "per-tool :structured overrides config :message" do
        tool = Class.new(described_class) do
          mcp_text_content :structured
          exposes :greeting, type: String
          success "Ignored"

          def call
            expose greeting: "Hi"
          end
        end

        response = tool.call(server_context:)
        expect(response.content.first[:text]).to eq('{"greeting":"Hi"}')
      end

      it "per-tool :message overrides config :structured" do
        # In this example only, override the around block so config is :structured (default)
        Axn::MCP.config.mcp_text_content = :structured

        tool = Class.new(described_class) do
          mcp_text_content :message
          exposes :greeting, type: String
          success "Custom"

          def call
            expose greeting: "Hi"
          end
        end

        response = tool.call(server_context:)
        expect(response.content.first[:text]).to eq("Custom")
      end
    end
  end

  describe "inheritance" do
    it "properly inherits from MCP::Tool" do
      expect(described_class.ancestors).to include(MCP::Tool)
    end

    it "includes Axn module" do
      expect(described_class.ancestors).to include(Axn)
    end
  end

  describe ".input_schema_value" do
    it "returns the same object as input_schema" do
      tool = Class.new(described_class) do
        expects :name, type: String
      end

      expect(tool.input_schema_value).to eq(tool.input_schema)
    end
  end

  describe ".output_schema_value" do
    it "returns nil when no exposes" do
      tool = Class.new(described_class) do
        expects :name, type: String
      end

      expect(tool.output_schema_value).to be_nil
    end

    it "returns the same object as output_schema when exposes exist" do
      tool = Class.new(described_class) do
        exposes :output, type: String
      end

      expect(tool.output_schema_value).to eq(tool.output_schema)
    end
  end

  describe "structured_content handling" do
    it "returns nil structured_content when no data is exposed" do
      tool = Class.new(described_class) do
        def call
          # success with no exposed data
        end
      end

      response = tool.call(server_context:)
      expect(response.structured_content).to be_nil
    end

    it "returns populated structured_content when data is exposed" do
      tool = Class.new(described_class) do
        exposes :value, type: String

        def call
          expose value: "test"
        end
      end

      response = tool.call(server_context:)
      expect(response.structured_content).to eq({ "value" => "test" })
    end
  end
end
