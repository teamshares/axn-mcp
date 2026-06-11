# frozen_string_literal: true

RSpec.describe Axn::MCP::SchemaBuilder do
  describe ".build_input" do
    describe "type mapping" do
      it "maps String to string" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :name, type: String
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:name][:type]).to eq("string")
      end

      it "maps Integer to integer" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :count, type: Integer
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:count][:type]).to eq("integer")
      end

      it "maps Float to number" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :amount, type: Float
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:amount][:type]).to eq("number")
      end

      it "maps Hash to object" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :data, type: Hash
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:data][:type]).to eq("object")
      end

      it "maps Array to array" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :items, type: Array
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:items][:type]).to eq("array")
      end

      it "maps :boolean to boolean" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :active, type: :boolean
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:active][:type]).to eq("boolean")
      end

      it "maps :uuid to string with uuid format" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :id, type: :uuid
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:id][:type]).to eq("string")
        expect(schema[:properties][:id][:format]).to eq("uuid")
      end

      it "maps Date to string with date format" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :birthday, type: Date
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:birthday][:type]).to eq("string")
        expect(schema[:properties][:birthday][:format]).to eq("date")
      end

      it "maps DateTime to string with date-time format" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :timestamp, type: DateTime
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:timestamp][:type]).to eq("string")
        expect(schema[:properties][:timestamp][:format]).to eq("date-time")
      end

      it "maps Time to string with date-time format" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :created_at, type: Time
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:created_at][:type]).to eq("string")
        expect(schema[:properties][:created_at][:format]).to eq("date-time")
      end

      it "maps Numeric to number" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :amount, type: Numeric
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:amount][:type]).to eq("number")
      end

      it "maps TrueClass to boolean" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :flag, type: TrueClass
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:flag][:type]).to eq("boolean")
      end

      it "maps FalseClass to boolean" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :flag, type: FalseClass
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:flag][:type]).to eq("boolean")
      end

      it "handles type in hash format" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :count, type: { klass: Integer }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:count][:type]).to eq("integer")
      end

      it "falls back to string for unknown types on input" do
        custom_class = Class.new
        tool = Class.new(Axn::MCP::Tool) do
          expects :custom, type: custom_class
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:custom][:type]).to eq("string")
      end
    end

    describe "required/optional" do
      it "marks required fields in required array" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :name, type: String
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:required]).to include("name")
      end

      it "excludes optional fields from required array" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :name, type: String, optional: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:required]).to be_nil
      end

      it "excludes fields with allow_blank from required array" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :name, type: String, allow_blank: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:required]).to be_nil
      end
    end

    describe "defaults" do
      it "includes default values in schema" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :status, type: String, default: "pending"
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:status][:default]).to eq("pending")
      end

      it "omits default when not provided" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :name, type: String
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:name]).not_to have_key(:default)
      end
    end

    describe "descriptions" do
      # Pass description: directly as a kwarg — NOT metadata: { description: "..." }.
      # The metadata: hash is not a recognized key and raises ArgumentError.
      it "includes description: kwarg in schema" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :name, type: String, description: "The user's full name"
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:name][:description]).to eq("The user's full name")
      end

      it "omits description when not provided" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :name, type: String
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:name]).not_to have_key(:description)
      end

      it "raises ArgumentError when metadata: hash is passed instead of description: kwarg" do
        expect do
          Class.new(Axn::MCP::Tool) do
            expects :name, type: String, metadata: { description: "The user's full name" }
          end
        end.to raise_error(ArgumentError, /metadata/)
      end
    end

    describe "enum from inclusion" do
      it "extracts enum from inclusion :in" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :status, inclusion: { in: %w[active inactive pending] }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:status][:enum]).to eq(%w[active inactive pending])
      end

      it "extracts enum from inclusion :within" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :priority, inclusion: { within: [1, 2, 3] }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:priority][:enum]).to eq([1, 2, 3])
      end

      it "infers type from enum values" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :status, inclusion: { in: %w[active inactive] }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:status][:type]).to eq("string")
      end

      it "infers integer type from integer enum values" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :priority, inclusion: { in: [1, 2, 3] }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:priority][:type]).to eq("integer")
      end

      it "infers number type from float enum values" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :rate, inclusion: { in: [0.5, 1.0, 1.5] }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:rate][:type]).to eq("number")
      end
    end

    describe "model: field handling" do
      let(:user_class) { Class.new }

      before do
        stub_const("User", user_class)
      end

      it "emits _id suffixed field instead of model field" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :user, model: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties]).to have_key(:user_id)
        expect(schema[:properties]).not_to have_key(:user)
      end

      it "sets type to integer for id field" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :user, model: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:user_id][:type]).to eq("integer")
      end

      it "auto-generates description for model field" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :user, model: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:user_id][:description]).to eq("ID of the User record")
      end

      it "allows custom description to override auto-generated" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :user, model: true, description: "The target user's ID"
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:user_id][:description]).to eq("The target user's ID")
      end

      it "marks model id field as required when model field is required" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :user, model: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:required]).to include("user_id")
      end
    end

    describe "subfield handling" do
      it "nests subfields under parent object" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :user, type: Hash
          expects :email, on: :user, type: String
          expects :name, on: :user, type: String
        end
        schema = described_class.build_input(tool.internal_field_configs, tool.subfield_configs)
        expect(schema[:properties][:user][:type]).to eq("object")
        expect(schema[:properties][:user][:properties][:email][:type]).to eq("string")
        expect(schema[:properties][:user][:properties][:name][:type]).to eq("string")
      end

      it "marks required subfields in nested required array" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :user, type: Hash
          expects :email, on: :user, type: String
          expects :nickname, on: :user, type: String, optional: true
        end
        schema = described_class.build_input(tool.internal_field_configs, tool.subfield_configs)
        expect(schema[:properties][:user][:required]).to include("email")
        expect(schema[:properties][:user][:required]).not_to include("nickname")
      end

      it "omits nested required array when all subfields are optional" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :user, type: Hash
          expects :email, on: :user, type: String, optional: true
          expects :name, on: :user, type: String, optional: true
        end
        schema = described_class.build_input(tool.internal_field_configs, tool.subfield_configs)
        expect(schema[:properties][:user][:required]).to be_nil
      end
    end

    describe "numericality validation" do
      it "infers integer from numericality with only_integer" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :count, numericality: { only_integer: true }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:count][:type]).to eq("integer")
      end

      it "infers number from numericality without only_integer" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :amount, numericality: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:amount][:type]).to eq("number")
      end

      it "infers number from numericality hash without only_integer" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :value, numericality: { greater_than: 0 }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:value][:type]).to eq("number")
      end
    end

    describe "presence/length type inference" do
      it "infers string from presence validation" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :name, presence: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:name][:type]).to eq("string")
      end

      it "infers string from length validation" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :code, length: { minimum: 3, maximum: 10 }
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:code][:type]).to eq("string")
      end
    end

    describe "fields with no type inference" do
      it "returns empty type info when no type can be inferred" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :unknown, optional: true
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:unknown]).not_to have_key(:type)
      end
    end
  end

  describe ".build_output" do
    it "builds schema from external field configs" do
      tool = Class.new(Axn::MCP::Tool) do
        exposes :output, type: String
        exposes :count, type: Integer
      end
      schema = described_class.build_output(tool.external_field_configs)
      expect(schema[:properties][:output][:type]).to eq("string")
      expect(schema[:properties][:count][:type]).to eq("integer")
    end

    it "includes descriptions" do
      tool = Class.new(Axn::MCP::Tool) do
        exposes :output, type: String, description: "The computed result"
      end
      schema = described_class.build_output(tool.external_field_configs)
      expect(schema[:properties][:output][:description]).to eq("The computed result")
    end

    it "falls back to object for unknown types on output" do
      custom_class = Class.new
      tool = Class.new(Axn::MCP::Tool) do
        exposes :custom, type: custom_class
      end
      schema = described_class.build_output(tool.external_field_configs)
      expect(schema[:properties][:custom][:type]).to eq("object")
    end

    it "marks non-optional fields as required" do
      tool = Class.new(Axn::MCP::Tool) do
        exposes :required_field, type: String
        exposes :optional_field, type: String, optional: true
      end
      schema = described_class.build_output(tool.external_field_configs)
      expect(schema[:required]).to include("required_field")
      expect(schema[:required]).not_to include("optional_field")
    end
  end

  describe "of: array element schema" do
    # scalar forms — both expects and exposes
    {
      String => { type: "string" },
      Integer => { type: "integer" },
      Float => { type: "number" },
      Numeric => { type: "number" },
    }.each do |ruby_type, expected_items|
      it "emits items #{expected_items.inspect} for of: #{ruby_type} on expects" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :tags, type: Array, of: ruby_type
        end
        schema = described_class.build_input(tool.internal_field_configs)
        expect(schema[:properties][:tags][:items]).to eq(expected_items)
      end

      it "emits items #{expected_items.inspect} for of: #{ruby_type} on exposes" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :tags, type: Array, of: ruby_type
        end
        schema = described_class.build_output(tool.external_field_configs)
        expect(schema[:properties][:tags][:items]).to eq(expected_items)
      end
    end

    it "emits items { type: 'boolean' } for of: :boolean" do
      tool = Class.new(Axn::MCP::Tool) do
        exposes :flags, type: Array, of: :boolean
      end
      schema = described_class.build_output(tool.external_field_configs)
      expect(schema[:properties][:flags][:items]).to eq({ type: "boolean" })
    end

    it "emits items { type: 'string', format: 'uuid' } for of: :uuid" do
      tool = Class.new(Axn::MCP::Tool) do
        exposes :ids, type: Array, of: :uuid
      end
      schema = described_class.build_output(tool.external_field_configs)
      expect(schema[:properties][:ids][:items]).to eq({ type: "string", format: "uuid" })
    end

    it "emits items { anyOf: [...] } for a union of: [String, Numeric]" do
      tool = Class.new(Axn::MCP::Tool) do
        exposes :values, type: Array, of: [String, Numeric]
      end
      schema = described_class.build_output(tool.external_field_configs)
      expect(schema[:properties][:values][:items]).to eq({
                                                           anyOf: [{ type: "string" }, { type: "number" }],
                                                         })
    end

    it "emits items with bare member properties for of: <Data.define subclass>" do
      record_klass = Data.define(:source, :status, :active)
      tool = Class.new(Axn::MCP::Tool) do
        exposes :records, type: Array, of: record_klass
      end
      schema = described_class.build_output(tool.external_field_configs)
      items = schema[:properties][:records][:items]
      expect(items[:type]).to eq("object")
      expect(items[:properties].keys).to contain_exactly(:source, :status, :active)
      expect(items[:properties][:source]).to eq({})
    end

    it "does not emit items for plain Array without of:" do
      tool = Class.new(Axn::MCP::Tool) do
        exposes :things, type: Array
      end
      schema = described_class.build_output(tool.external_field_configs)
      expect(schema[:properties][:things]).not_to have_key(:items)
    end

    it "still emits default: on non-member (FieldConfig) fields" do
      tool = Class.new(Axn::MCP::Tool) do
        expects :status, type: String, default: "pending"
      end
      schema = described_class.build_input(tool.internal_field_configs)
      expect(schema[:properties][:status][:default]).to eq("pending")
    end
  end

  describe "shape: block schema" do
    describe "Array field with shape: block (no of:)" do
      it "emits items.properties with typed members" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :entries, type: Array do
            field :name, type: String
            field :count, type: Integer
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        items = schema[:properties][:entries][:items]
        expect(items[:type]).to eq("object")
        expect(items[:properties][:name][:type]).to eq("string")
        expect(items[:properties][:count][:type]).to eq("integer")
      end

      it "derives items.required from required members" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :entries, type: Array do
            field :name, type: String
            field :label, type: String, optional: true
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        items = schema[:properties][:entries][:items]
        expect(items[:required]).to include("name")
        expect(items[:required]).not_to include("label")
      end

      it "omits items.required when all members are optional" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :entries, type: Array do
            field :name, type: String, optional: true
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        items = schema[:properties][:entries][:items]
        expect(items).not_to have_key(:required)
      end

      it "includes enum in member property from inclusion:" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :entries, type: Array do
            field :status, type: String, inclusion: { in: %w[active inactive] }
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        items = schema[:properties][:entries][:items]
        expect(items[:properties][:status][:enum]).to eq(%w[active inactive])
        expect(items[:properties][:status][:type]).to eq("string")
      end

      it "works on expects (input) as well as exposes (output)" do
        tool = Class.new(Axn::MCP::Tool) do
          expects :filters, type: Array do
            field :key, type: String
            field :value, type: String
          end
        end
        schema = described_class.build_input(tool.internal_field_configs)
        items = schema[:properties][:filters][:items]
        expect(items[:type]).to eq("object")
        expect(items[:properties][:key][:type]).to eq("string")
        expect(items[:properties][:value][:type]).to eq("string")
      end
    end

    describe "Hash field with shape: block" do
      it "emits properties directly on the Hash property" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :config, type: Hash do
            field :region, type: String
            field :timeout, type: Integer
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        prop = schema[:properties][:config]
        expect(prop[:type]).to eq("object")
        expect(prop[:properties][:region][:type]).to eq("string")
        expect(prop[:properties][:timeout][:type]).to eq("integer")
      end

      it "derives required from required Hash members" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :config, type: Hash do
            field :region, type: String
            field :label, type: String, optional: true
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        prop = schema[:properties][:config]
        expect(prop[:required]).to include("region")
        expect(prop[:required]).not_to include("label")
      end
    end

    describe "nested shape blocks" do
      it "recurses into nested Hash member" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :entries, type: Array do
            field :name, type: String
            field :config, type: Hash do
              field :region, type: String
            end
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        items = schema[:properties][:entries][:items]
        expect(items[:properties][:config][:type]).to eq("object")
        expect(items[:properties][:config][:properties][:region][:type]).to eq("string")
      end
    end

    describe "of: + shape: (enrich case)" do
      let(:record_klass) { Data.define(:source, :status, :active) }

      it "starts from Data members as bare baseline and overlays block members" do
        klass = record_klass
        tool = Class.new(Axn::MCP::Tool) do
          exposes :records, type: Array, of: klass do
            field :status, type: String, inclusion: { in: %w[on off] }
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        items = schema[:properties][:records][:items]

        expect(items[:type]).to eq("object")
        # annotated member is typed
        expect(items[:properties][:status][:type]).to eq("string")
        expect(items[:properties][:status][:enum]).to eq(%w[on off])
        # unannotated Data members stay bare {}
        expect(items[:properties][:source]).to eq({})
        expect(items[:properties][:active]).to eq({})
      end

      it "includes all Data members even when only some are annotated in shape:" do
        klass = record_klass
        tool = Class.new(Axn::MCP::Tool) do
          exposes :records, type: Array, of: klass do
            field :source, type: String
          end
        end
        schema = described_class.build_output(tool.external_field_configs)
        items = schema[:properties][:records][:items]
        expect(items[:properties].keys).to include(:source, :status, :active)
      end
    end
  end
end
