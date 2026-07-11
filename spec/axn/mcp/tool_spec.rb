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

      it "still takes the MCP-mode branch when server_context arrives under a string key" do
        tool = Class.new(described_class) do
          expects :name, type: String

          def call
            # no-op, success
          end
        end

        response = tool.call("name" => "Alice", "server_context" => server_context)
        expect(response).to be_a(MCP::Tool::Response)
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
      it "returns error response when action fails, prefixing the reason with the base headline" do
        tool = Class.new(described_class) do
          def call
            fail! "email taken"
          end
        end

        response = tool.call(server_context:)
        expect(response.error?).to be true
        expect(response.content.first[:text]).to eq("Tool call failed: email taken")
      end

      it "uses the base headline alone when no reason is provided" do
        tool = Class.new(described_class) do
          def call
            fail!
          end
        end

        response = tool.call(server_context:)
        expect(response.error?).to be true
        expect(response.content.first[:text]).to eq("Tool call failed")
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
        # server_context now flows through axn core's ambient_context resolution, which normalizes the
        # hash via with_indifferent_access -- string-keyed comparison, not the original symbol keys.
        expect(received_context).to eq({ "user_id" => 123 })
      end

      it "does not include server_context in input schema" do
        tool = Class.new(described_class) do
          expects :name, type: String
        end

        schema = tool.input_schema.to_h
        expect(schema[:properties]).to have_key(:name)
        expect(schema[:properties]).not_to have_key(:server_context)
      end

      it "is excluded from input_schema via the ambient_context mechanism, not a hardcoded list" do
        tool = Class.new(described_class) do
          expects :name, type: String
          def call = nil
        end

        # No :server_context key anywhere in internal_field_configs -- it's not a top-level field at all.
        expect(tool.internal_field_configs.map(&:field)).not_to include(:server_context)
        expect(tool.input_schema_value.to_h[:properties]).not_to have_key(:server_context)
      end

      it "does not leak Rails Current state into ambient_context when called via MCP" do
        current_class = Class.new(ActiveSupport::CurrentAttributes) { attribute :leaky }
        stub_const("ToolSpecLeakyCurrent", current_class)
        current_class.leaky = "should never appear"

        tool = Class.new(described_class) do
          expects :leaky, on: :ambient_context, type: String, optional: true
          exposes :res, type: String, optional: true
          def call
            expose res: leaky
          end
        end

        response = tool.call(server_context: { user_id: 1 })
        expect(JSON.parse(response.content.first[:text])["res"]).to be_nil
      ensure
        current_class&.reset
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

    it "does not leak Rails Current state into ambient_context when called directly (no server_context: at all)" do
      current_class = Class.new(ActiveSupport::CurrentAttributes) { attribute :leaky }
      stub_const("ToolSpecDirectLeakyCurrent", current_class)
      current_class.leaky = "should never appear"

      tool = Class.new(described_class) do
        expects :leaky, on: :ambient_context, type: String, optional: true
        exposes :res, type: String, optional: true
        def call
          expose res: leaky
        end
      end

      result = tool.call
      expect(result.res).to be_nil
    ensure
      current_class&.reset
    end

    it "returns failed Axn::Result on fail!" do
      tool = Class.new(described_class) do
        def call
          fail! "email taken"
        end
      end

      result = tool.call
      expect(result).to be_a(Axn::Result)
      expect(result).not_to be_ok
      expect(result.message).to eq("Tool call failed: email taken")
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

        expect { tool.call! }.to raise_error(Axn::Failure, "Tool call failed: Controlled failure")
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

    describe "type mapping" do
      {
        String => { type: "string" },
        Integer => { type: "integer" },
        Float => { type: "number" },
        Hash => { type: "object" },
        Array => { type: "array" },
        Numeric => { type: "number" },
      }.each do |ruby_type, expected|
        it "maps #{ruby_type} to #{expected[:type]}" do
          tool = Class.new(described_class) { expects :field, type: ruby_type }
          properties = tool.input_schema_value.to_h[:properties]
          expect(properties[:field][:type]).to eq(expected[:type])
        end
      end

      it "maps :boolean to boolean" do
        tool = Class.new(described_class) { expects :active, type: :boolean }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:active][:type]).to eq("boolean")
      end

      it "maps :uuid to string with uuid format" do
        tool = Class.new(described_class) { expects :id, type: :uuid }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:id][:type]).to eq("string")
        expect(properties[:id][:format]).to eq("uuid")
      end

      it "maps Date to string with date format" do
        tool = Class.new(described_class) { expects :birthday, type: Date }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:birthday][:type]).to eq("string")
        expect(properties[:birthday][:format]).to eq("date")
      end

      it "maps DateTime to string with date-time format" do
        tool = Class.new(described_class) { expects :timestamp, type: DateTime }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:timestamp][:type]).to eq("string")
        expect(properties[:timestamp][:format]).to eq("date-time")
      end

      it "maps Time to string with date-time format" do
        tool = Class.new(described_class) { expects :created_at, type: Time }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:created_at][:type]).to eq("string")
        expect(properties[:created_at][:format]).to eq("date-time")
      end

      # NOTE: TrueClass/FalseClass gain an explicit enum (core's TypeValidator only accepts the
      # singleton value, so a bare "boolean" type would wrongly let a client send the other value too).
      it "maps TrueClass to boolean with a true-only enum" do
        tool = Class.new(described_class) { expects :flag, type: TrueClass }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:flag][:type]).to eq("boolean")
        expect(properties[:flag][:enum]).to eq([true])
      end

      it "maps FalseClass to boolean with a false-only enum" do
        tool = Class.new(described_class) { expects :flag, type: FalseClass }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:flag][:type]).to eq("boolean")
        expect(properties[:flag][:enum]).to eq([false])
      end

      it "handles type in hash format" do
        tool = Class.new(described_class) { expects :count, type: { klass: Integer } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:count][:type]).to eq("integer")
      end

      it "falls back to string for unknown types on input" do
        custom_class = Class.new
        tool = Class.new(described_class) { expects :custom, type: custom_class }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:custom][:type]).to eq("string")
      end
    end

    describe "required/optional/nullable" do
      it "marks required fields in required array" do
        tool = Class.new(described_class) { expects :name, type: String }
        expect(tool.input_schema_value.to_h[:required]).to include("name")
      end

      # A nullable field now reflects as a `type` ARRAY (e.g. ["string", "null"]) rather than a bare
      # type -- core adds "null" to the JSON type whenever the field's validators tolerate nil/blank.
      it "excludes optional fields from required array and reflects nullability as a type array" do
        tool = Class.new(described_class) { expects :name, type: String, optional: true }
        schema = tool.input_schema_value.to_h
        expect(schema[:required]).to be_nil
        expect(schema[:properties][:name][:type]).to eq(%w[string null])
      end

      it "excludes fields with allow_blank from required array and reflects nullability as a type array" do
        tool = Class.new(described_class) { expects :name, type: String, allow_blank: true }
        schema = tool.input_schema_value.to_h
        expect(schema[:required]).to be_nil
        expect(schema[:properties][:name][:type]).to eq(%w[string null])
      end

      it "does not include server_context in input schema" do
        tool = Class.new(described_class) { expects :name, type: String }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties).to have_key(:name)
        expect(properties).not_to have_key(:server_context)
      end
    end

    describe "defaults" do
      it "includes default values in schema" do
        tool = Class.new(described_class) { expects :status, type: String, default: "pending" }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:status][:default]).to eq("pending")
      end

      it "omits default when not provided" do
        tool = Class.new(described_class) { expects :name, type: String }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:name]).not_to have_key(:default)
      end
    end

    describe "descriptions" do
      # Pass description: directly as a kwarg -- NOT metadata: { description: "..." }.
      # The metadata: hash is not a recognized key and raises ArgumentError.
      it "includes description: kwarg in schema" do
        tool = Class.new(described_class) { expects :name, type: String, description: "The user's full name" }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:name][:description]).to eq("The user's full name")
      end

      it "omits description when not provided" do
        tool = Class.new(described_class) { expects :name, type: String }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:name]).not_to have_key(:description)
      end

      it "raises ArgumentError when metadata: hash is passed instead of description: kwarg" do
        expect do
          Class.new(described_class) do
            expects :name, type: String, metadata: { description: "The user's full name" }
          end
        end.to raise_error(ArgumentError, /metadata/)
      end
    end

    describe "enum from inclusion" do
      it "extracts enum from inclusion :in" do
        tool = Class.new(described_class) { expects :status, inclusion: { in: %w[active inactive pending] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:status][:enum]).to eq(%w[active inactive pending])
      end

      it "extracts enum from inclusion :within" do
        tool = Class.new(described_class) { expects :priority, inclusion: { within: [1, 2, 3] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:priority][:enum]).to eq([1, 2, 3])
      end

      it "infers type from enum values" do
        tool = Class.new(described_class) { expects :status, inclusion: { in: %w[active inactive] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:status][:type]).to eq("string")
      end

      it "infers integer type from integer enum values" do
        tool = Class.new(described_class) { expects :priority, inclusion: { in: [1, 2, 3] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:priority][:type]).to eq("integer")
      end

      it "infers number type from float enum values" do
        tool = Class.new(described_class) { expects :rate, inclusion: { in: [0.5, 1.0, 1.5] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:rate][:type]).to eq("number")
      end
    end

    describe "model: field handling" do
      let(:user_class) { Class.new }

      before do
        stub_const("User", user_class)
      end

      it "emits _id suffixed field instead of model field" do
        tool = Class.new(described_class) { expects :user, model: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties).to have_key(:user_id)
        expect(properties).not_to have_key(:user)
      end

      # NOTE: core does NOT constrain the generated id field's JSON type (the old builder hard-coded
      # "integer") -- a model's primary key isn't knowable from the declaration (could be a UUID,
      # string, etc.) and inferring it would require a DB load, so it's left untyped. A required
      # model id also gets `not: { type: "null" }` since a null token can't resolve to a record.
      it "leaves the generated id field's type unconstrained but non-null when required" do
        tool = Class.new(described_class) { expects :user, model: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user_id]).not_to have_key(:type)
        expect(properties[:user_id][:not]).to eq({ type: "null" })
      end

      it "auto-generates description for model field" do
        tool = Class.new(described_class) { expects :user, model: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user_id][:description]).to eq("ID of the User record")
      end

      it "allows custom description to override auto-generated" do
        tool = Class.new(described_class) { expects :user, model: true, description: "The target user's ID" }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user_id][:description]).to eq("The target user's ID")
      end

      it "marks model id field as required when model field is required" do
        tool = Class.new(described_class) { expects :user, model: true }
        expect(tool.input_schema_value.to_h[:required]).to include("user_id")
      end
    end

    describe "subfield handling" do
      it "nests subfields under parent object" do
        tool = Class.new(described_class) do
          expects :user, type: Hash
          expects :email, on: :user, type: String
          expects :name, on: :user, type: String
        end
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user][:type]).to eq("object")
        expect(properties[:user][:properties][:email][:type]).to eq("string")
        expect(properties[:user][:properties][:name][:type]).to eq("string")
      end

      it "marks required subfields in nested required array" do
        tool = Class.new(described_class) do
          expects :user, type: Hash
          expects :email, on: :user, type: String
          expects :nickname, on: :user, type: String, optional: true
        end
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user][:required]).to include("email")
        expect(properties[:user][:required]).not_to include("nickname")
      end

      it "omits nested required array when all subfields are optional" do
        tool = Class.new(described_class) do
          expects :user, type: Hash
          expects :email, on: :user, type: String, optional: true
          expects :name, on: :user, type: String, optional: true
        end
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user][:required]).to be_nil
      end
    end

    describe "numericality validation" do
      it "infers integer from numericality with only_integer" do
        tool = Class.new(described_class) { expects :count, numericality: { only_integer: true } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:count][:type]).to eq("integer")
      end

      it "infers number from numericality without only_integer" do
        tool = Class.new(described_class) { expects :amount, numericality: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:amount][:type]).to eq("number")
      end

      it "infers number from numericality hash without only_integer" do
        tool = Class.new(described_class) { expects :value, numericality: { greater_than: 0 } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:value][:type]).to eq("number")
      end
    end

    describe "presence/length validations (no longer infer a JSON type)" do
      # NOTE: core's json_type_for has no presence:/length: fallback branch (removed along with the
      # old builder) -- those validators inform requiredness/nullability only, never JSON *type*
      # (presence/length say nothing about the field's shape). This intentionally diverges from the
      # old builder, which guessed "string" for any presence/length-validated field.
      it "returns empty type info for a presence-only field" do
        tool = Class.new(described_class) { expects :name, presence: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:name]).not_to have_key(:type)
      end

      it "returns empty type info for a length-only field" do
        tool = Class.new(described_class) { expects :code, length: { minimum: 3, maximum: 10 } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:code]).not_to have_key(:type)
      end
    end

    describe "fields with no type inference" do
      it "returns empty type info when no type can be inferred" do
        tool = Class.new(described_class) { expects :unknown, optional: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:unknown]).not_to have_key(:type)
      end
    end

    describe "of: array element schema" do
      {
        String => { type: "string" },
        Integer => { type: "integer" },
        Float => { type: "number" },
        Numeric => { type: "number" },
      }.each do |ruby_type, expected_items|
        it "emits items #{expected_items.inspect} for of: #{ruby_type}" do
          tool = Class.new(described_class) { expects :tags, type: Array, of: ruby_type }
          properties = tool.input_schema_value.to_h[:properties]
          expect(properties[:tags][:items]).to eq(expected_items)
        end
      end

      it "does not emit items for plain Array without of:" do
        tool = Class.new(described_class) { expects :things, type: Array }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:things]).not_to have_key(:items)
      end
    end

    describe "shape: block schema (works on input regardless of of:)" do
      it "emits items.properties with typed members for an Array field with shape: (no of:)" do
        tool = Class.new(described_class) do
          expects :filters, type: Array do
            field :key, type: String
            field :value, type: String
          end
        end
        items = tool.input_schema_value.to_h[:properties][:filters][:items]
        expect(items[:type]).to eq("object")
        expect(items[:properties][:key][:type]).to eq("string")
        expect(items[:properties][:value][:type]).to eq("string")
      end

      it "recurses into a nested Hash member's shape: block" do
        tool = Class.new(described_class) do
          expects :entries, type: Array do
            field :name, type: String
            field :config, type: Hash do
              field :region, type: String
            end
          end
        end
        items = tool.input_schema_value.to_h[:properties][:entries][:items]
        expect(items[:properties][:config][:type]).to eq("object")
        expect(items[:properties][:config][:properties][:region][:type]).to eq("string")
      end

      it "combines of: + shape: enrich, keeping unannotated Data members bare" do
        record_klass = Data.define(:source, :status, :active)
        tool = Class.new(described_class) do
          expects :records, type: Array, of: record_klass do
            field :status, type: String, inclusion: { in: %w[on off] }
          end
        end
        items = tool.input_schema_value.to_h[:properties][:records][:items]
        expect(items[:properties][:status][:type]).to eq("string")
        expect(items[:properties][:status][:enum]).to eq(%w[on off])
        expect(items[:properties][:source]).to eq({})
        expect(items[:properties][:active]).to eq({})
      end
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

    describe "basic output shape" do
      it "builds schema from external field configs" do
        tool = Class.new(described_class) do
          exposes :output, type: String
          exposes :count, type: Integer
        end
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:output][:type]).to eq("string")
        expect(properties[:count][:type]).to eq("integer")
      end

      it "includes descriptions" do
        tool = Class.new(described_class) { exposes :output, type: String, description: "The computed result" }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:output][:description]).to eq("The computed result")
      end

      it "falls back to untyped for unknown types on output" do
        # NOTE: differs from the old builder, which fell back to type: "object". Core cannot prove an
        # arbitrary class's serialized wire shape (its as_json/to_h could emit a scalar, array, or
        # differently-shaped hash), so it leaves the property untyped rather than assert "object" the
        # serialized value might contradict (see single_type_for's "Unknown class" comment).
        custom_class = Class.new
        tool = Class.new(described_class) { exposes :custom, type: custom_class }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:custom]).not_to have_key(:type)
      end

      it "marks every exposed field required (JSON Schema `required` means presence, not non-null) and reflects optionality as nullability" do
        # NOTE: differs from the old builder, which omitted optional fields from `required`. Every
        # exposes key is always present in serialize_exposed's output (nil when unset), so JSON Schema
        # `required` (property PRESENCE) is always true; the optional field's OPTIONALITY instead shows
        # up as a nullable type.
        tool = Class.new(described_class) do
          exposes :required_field, type: String
          exposes :optional_field, type: String, optional: true
        end
        schema = tool.output_schema_value.to_h
        expect(schema[:required]).to contain_exactly("required_field", "optional_field")
        expect(schema[:properties][:required_field][:type]).to eq("string")
        expect(schema[:properties][:optional_field][:type]).to eq(%w[string null])
      end
    end

    describe "of: array element schema" do
      {
        String => { type: "string" },
        Integer => { type: "integer" },
        Float => { type: "number" },
      }.each do |ruby_type, expected_items|
        it "emits items #{expected_items.inspect} for of: #{ruby_type}" do
          tool = Class.new(described_class) { exposes :tags, type: Array, of: ruby_type }
          properties = tool.output_schema_value.to_h[:properties]
          expect(properties[:tags][:items]).to eq(expected_items)
        end
      end

      # NOTE: differs from the old builder, which mapped of: Numeric to items: { type: "number" } on
      # output too. Core leaves a Numeric-typed output element untyped: `Numeric` admits a `Complex`
      # value, whose serialized wire form (a JSON number vs. a String via to_s) isn't knowable from the
      # declaration alone, so it's left untyped rather than assert "number" (see single_type_for).
      it "omits items entirely for of: Numeric (Numeric admits Complex, unknowable on output)" do
        tool = Class.new(described_class) { exposes :tags, type: Array, of: Numeric }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:tags]).not_to have_key(:items)
      end

      it "emits items { type: 'boolean' } for of: :boolean" do
        tool = Class.new(described_class) { exposes :flags, type: Array, of: :boolean }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:flags][:items]).to eq({ type: "boolean" })
      end

      it "emits items { type: 'string', format: 'uuid' } for of: :uuid" do
        tool = Class.new(described_class) { exposes :ids, type: Array, of: :uuid }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:ids][:items]).to eq({ type: "string", format: "uuid" })
      end

      it "emits items { anyOf: [...] } for a union of: [String, Numeric], leaving the Numeric member untyped" do
        # NOTE: the Numeric member is `{}` rather than `{ type: "number" }` -- same Complex-admitting
        # rationale as the standalone of: Numeric case above.
        tool = Class.new(described_class) { exposes :values, type: Array, of: [String, Numeric] }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:values][:items]).to eq({ anyOf: [{ type: "string" }, {}] })
      end

      it "emits items with bare member properties for of: <Data.define subclass>" do
        record_klass = Data.define(:source, :status, :active)
        tool = Class.new(described_class) { exposes :records, type: Array, of: record_klass }
        items = tool.output_schema_value.to_h[:properties][:records][:items]
        expect(items[:type]).to eq("object")
        expect(items[:properties].keys).to contain_exactly(:source, :status, :active)
        expect(items[:properties][:source]).to eq({})
      end

      it "does not emit items for plain Array without of:" do
        tool = Class.new(described_class) { exposes :things, type: Array }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:things]).not_to have_key(:items)
      end
    end

    describe "shape: block schema" do
      it "does NOT overlay shape: onto an Array field's items when there is no of: (output cannot prove the elements serialize member-keyed)" do
        # NOTE: this is the one confirmed coverage LOSS vs. the old builder, which unconditionally
        # nested shape: members under items regardless of of:. Core only overlays object properties
        # onto output array items when of: names a provably member-keyed element type (plain Data/
        # Struct/Hash) -- see shape_overlay_applies?'s "OUTPUT: each element must provably serialize to
        # a member-keyed object (a plain Data/Struct/Hash `of:`)". A bare `type: Array do ... end` block
        # has no of:, so the shape is silently dropped from the OUTPUT schema; declare `of:` alongside
        # shape: (see the of: + shape: examples below) to get typed output items, or rely on the input
        # schema (still fully supported, see .input_schema examples above).
        tool = Class.new(described_class) do
          exposes :entries, type: Array do
            field :name, type: String
            field :count, type: Integer
          end
        end
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:entries]).to eq({ type: "array" })
      end

      it "emits properties directly on a Hash field's shape: block" do
        tool = Class.new(described_class) do
          exposes :config, type: Hash do
            field :region, type: String
            field :timeout, type: Integer
          end
        end
        prop = tool.output_schema_value.to_h[:properties][:config]
        expect(prop[:type]).to eq("object")
        expect(prop[:properties][:region][:type]).to eq("string")
        expect(prop[:properties][:timeout][:type]).to eq("integer")
      end

      it "derives required from required Hash shape: members" do
        tool = Class.new(described_class) do
          exposes :config, type: Hash do
            field :region, type: String
            field :label, type: String, optional: true
          end
        end
        prop = tool.output_schema_value.to_h[:properties][:config]
        expect(prop[:required]).to include("region")
        expect(prop[:required]).not_to include("label")
      end

      it "uses Data members as a bare baseline so unannotated members still appear" do
        record_klass = Data.define(:source, :provider_name, :active, :status)
        tool = Class.new(described_class) do
          exposes :integration, type: record_klass do
            field :status, type: String, inclusion: { in: %w[connected error] }
          end
        end
        prop = tool.output_schema_value.to_h[:properties][:integration]
        expect(prop[:properties][:status][:enum]).to eq(%w[connected error])
        expect(prop[:properties][:source]).to eq({})
        expect(prop[:properties][:provider_name]).to eq({})
        expect(prop[:properties][:active]).to eq({})
      end

      it "of: + shape: (enrich case) starts from Data members as bare baseline and overlays block members" do
        record_klass = Data.define(:source, :status, :active)
        tool = Class.new(described_class) do
          exposes :records, type: Array, of: record_klass do
            field :status, type: String, inclusion: { in: %w[on off] }
          end
        end
        items = tool.output_schema_value.to_h[:properties][:records][:items]
        expect(items[:type]).to eq("object")
        expect(items[:properties][:status][:type]).to eq("string")
        expect(items[:properties][:status][:enum]).to eq(%w[on off])
        expect(items[:properties][:source]).to eq({})
        expect(items[:properties][:active]).to eq({})
      end

      it "includes all Data members even when only some are annotated in of: + shape:" do
        record_klass = Data.define(:source, :status, :active)
        tool = Class.new(described_class) do
          exposes :records, type: Array, of: record_klass do
            field :source, type: String
          end
        end
        items = tool.output_schema_value.to_h[:properties][:records][:items]
        expect(items[:properties].keys).to include(:source, :status, :active)
      end
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

  describe ".description" do
    it "routes the description DSL to MCP transport, not axn's own internal Naming#description" do
      tool = Class.new(described_class) do
        description "A test tool"
        def call = nil
      end

      expect(tool.description_value).to eq("A test tool")
      expect(tool.to_h[:description]).to eq("A test tool")
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

    describe "deprecation: bang methods are thin aliases over semantic_hints" do
      it "warns with a message pointing at the semantic_hints replacement, for each bang method" do
        expect(Axn::MCP.deprecator).to receive(:warn).with(/read_only!.*semantic_hints :read_only/)
        Class.new(described_class) { read_only! }

        expect(Axn::MCP.deprecator).to receive(:warn).with(/destructive!.*semantic_hints :destructive/)
        Class.new(described_class) { destructive! }

        expect(Axn::MCP.deprecator).to receive(:warn).with(/idempotent!.*semantic_hints :idempotent/)
        Class.new(described_class) { idempotent! }

        expect(Axn::MCP.deprecator).to receive(:warn).with(/open_world!.*open_world/)
        Class.new(described_class) { open_world! }

        expect(Axn::MCP.deprecator).to receive(:warn).with(/closed_world!.*closed_world/)
        Class.new(described_class) { closed_world! }
      end

      before { allow(Axn::MCP.deprecator).to receive(:warn) }

      it "read_only! also updates .semantic_hints and is mutually exclusive with destructive!" do
        tool = Class.new(described_class) do
          destructive!
          read_only!
        end

        expect(tool.semantic_hints).to include(:read_only)
        expect(tool.semantic_hints).not_to include(:destructive)
        expect(tool.annotations_value.read_only_hint).to be true
        expect(tool.annotations_value.destructive_hint).to be false
      end

      it "destructive! also updates .semantic_hints and is mutually exclusive with read_only!" do
        tool = Class.new(described_class) do
          read_only!
          destructive!
        end

        expect(tool.semantic_hints).to include(:destructive)
        expect(tool.semantic_hints).not_to include(:read_only)
        expect(tool.annotations_value.destructive_hint).to be true
        expect(tool.annotations_value.read_only_hint).to be false
      end

      it "idempotent! also updates .semantic_hints and composes with read_only! (unlike the old full-replace behavior)" do
        tool = Class.new(described_class) do
          read_only!
          idempotent!
        end

        expect(tool.semantic_hints).to include(:read_only, :idempotent)
        expect(tool.annotations_value.read_only_hint).to be true
        expect(tool.annotations_value.idempotent_hint).to be true
      end

      it "open_world! also updates .semantic_hints and is mutually exclusive with closed_world!" do
        tool = Class.new(described_class) do
          closed_world!
          open_world!
        end

        expect(tool.semantic_hints).to include(:open_world)
        expect(tool.semantic_hints).not_to include(:closed_world)
        expect(tool.annotations_value.open_world_hint).to be true
      end

      it "closed_world! also updates .semantic_hints and is mutually exclusive with open_world!" do
        tool = Class.new(described_class) do
          open_world!
          closed_world!
        end

        expect(tool.semantic_hints).to include(:closed_world)
        expect(tool.semantic_hints).not_to include(:open_world)
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

  describe "semantic_hints -> MCP annotations default mapping" do
    it "derives read_only_hint from a declared semantic_hints :read_only" do
      tool = Class.new(Axn::MCP::Tool) do
        semantic_hints :read_only
        def call = nil
      end

      expect(tool.annotations_value.read_only_hint).to be true
      expect(tool.annotations_value.destructive_hint).to be false
    end

    it "does not override an explicitly-declared annotations(...) call" do
      tool = Class.new(Axn::MCP::Tool) do
        semantic_hints :read_only
        annotations(title: "Explicit Title")
        def call = nil
      end

      expect(tool.annotations_value.read_only_hint).to be false # explicit annotations() call wins, reverts to MCP default
      expect(tool.annotations_value.title).to eq("Explicit Title")
    end

    it "supports open_world as a semantic hint, registered via the extension registry (no core change)" do
      tool = Class.new(Axn::MCP::Tool) do
        open_world
        def call = nil
      end

      expect(tool.semantic_hints).to include(:open_world)
      expect(tool.annotations_value.open_world_hint).to be true
    end

    it "supports closed_world as a semantic hint" do
      tool = Class.new(Axn::MCP::Tool) do
        closed_world
        def call = nil
      end

      expect(tool.semantic_hints).to include(:closed_world)
      expect(tool.annotations_value.open_world_hint).to be false
    end

    it "re-derives annotations after a second semantic hint declaration, not just the first" do
      tool = Class.new(Axn::MCP::Tool) do
        open_world
        closed_world
        def call = nil
      end

      expect(tool.semantic_hints).to include(:closed_world)
      expect(tool.semantic_hints).not_to include(:open_world)
      expect(tool.annotations_value.open_world_hint).to be false
    end

    it "re-derives annotations after semantic_hints is called again with different hints" do
      tool = Class.new(Axn::MCP::Tool) do
        semantic_hints :read_only
        semantic_hints :idempotent
        def call = nil
      end

      expect(tool.annotations_value.read_only_hint).to be false
      expect(tool.annotations_value.idempotent_hint).to be true
    end

    it "applies a base class's declared semantic_hints to subclasses that never redeclare them" do
      base = Class.new(Axn::MCP::Tool) do
        semantic_hints :read_only
        def call = nil
      end
      subclass = Class.new(base)

      expect(subclass.semantic_hints).to include(:read_only)
      expect(subclass.annotations_value.read_only_hint).to be true
      expect(subclass.annotations_value.destructive_hint).to be false
    end

    it "applies a base class's explicit annotations(...) to subclasses that never redeclare them" do
      base = Class.new(Axn::MCP::Tool) do
        annotations(title: "Custom Title", read_only_hint: true)
        def call = nil
      end
      subclass = Class.new(base)

      expect(subclass.annotations_value).not_to be_nil
      expect(subclass.annotations_value.title).to eq("Custom Title")
      expect(subclass.annotations_value.read_only_hint).to be true
    end

    it "agrees with .annotations (not just .annotations_value), since MCP::Server's own protocol-version validation reads .annotations" do
      tool = Class.new(Axn::MCP::Tool) do
        semantic_hints :read_only
        def call = nil
      end

      expect(tool.annotations).not_to be_nil
      expect(tool.annotations.read_only_hint).to be true
      expect(tool.annotations.destructive_hint).to be false
    end

    it "leaves annotations absent (not SDK defaults) when a declared semantic hint maps to no MCP annotation" do
      Axn.extension_config.register_semantic_hint(:cacheable)
      tool = Class.new(Axn::MCP::Tool) do
        semantic_hints :cacheable
        def call = nil
      end

      expect(tool.annotations_value).to be_nil
      expect(tool.annotations).to be_nil
    end

    it "keeps the legacy read_only! bang method's exact prior behavior" do
      tool = Class.new(Axn::MCP::Tool) do
        read_only!
        def call = nil
      end

      expect(tool.annotations_value.read_only_hint).to be true
      expect(tool.annotations_value.destructive_hint).to be false
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

    it "resolves mcp_text_content up the full superclass chain, not just one level" do
      middle = Class.new(described_class) { mcp_text_content :message }
      grandchild = Class.new(middle)

      expect(grandchild.resolved_mcp_text_content).to eq(:message)
    end

    it "falls back to library config when no ancestor in the chain has an override" do
      middle = Class.new(described_class)
      grandchild = Class.new(middle)

      expect(grandchild.resolved_mcp_text_content).to eq(Axn::MCP.config.mcp_text_content)
    end

    it "lets a grandchild's own override win over an ancestor's" do
      middle = Class.new(described_class) { mcp_text_content :message }
      grandchild = Class.new(middle) { mcp_text_content :structured }

      expect(grandchild.resolved_mcp_text_content).to eq(:structured)
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
