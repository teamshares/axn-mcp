# frozen_string_literal: true

RSpec.describe "Axn::MCP.wrap schema reflection" do
  # Builds a plain Axn from the block body and wraps it as an ::MCP::Tool for schema assertions.
  def wrapped(&body)
    axn = Class.new { include Axn }
    axn.class_eval(&body)
    Axn::MCP.wrap(axn, name: "probe", description: "probe")
  end

  describe "retired Axn::MCP::Tool base" do
    it "raises when subclassing the retired base" do
      expect { Class.new(Axn::MCP::Tool) }.to raise_error(NotImplementedError, /retired/i)
    end

    it "raises when calling .define on the retired base" do
      expect { Axn::MCP::Tool.define(description: "x") }.to raise_error(NotImplementedError, /retired/i)
    end
  end

  describe ".input_schema" do
    it "returns auto-generated InputSchema" do
      tool = wrapped do
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

    it "reflects a conditionally required field as an allOf clause, not an unconditional required entry" do
      tool = wrapped do
        expects :use_token, type: :boolean, optional: true
        expects :token, type: String, if: :use_token
      end

      schema = tool.input_schema.to_h
      expect(Array(schema[:required])).not_to include("token")
      expect(schema[:allOf]).to be_present
      expect(schema[:allOf].first[:then][:required]).to eq(["token"])
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
          tool = wrapped { expects :field, type: ruby_type }
          properties = tool.input_schema_value.to_h[:properties]
          expect(properties[:field][:type]).to eq(expected[:type])
        end
      end

      it "maps :boolean to boolean" do
        tool = wrapped { expects :active, type: :boolean }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:active][:type]).to eq("boolean")
      end

      it "maps :uuid to string with uuid format" do
        tool = wrapped { expects :id, type: :uuid }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:id][:type]).to eq("string")
        expect(properties[:id][:format]).to eq("uuid")
      end

      it "maps Date to string with date format" do
        tool = wrapped { expects :birthday, type: Date }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:birthday][:type]).to eq("string")
        expect(properties[:birthday][:format]).to eq("date")
      end

      it "maps DateTime to string with date-time format" do
        tool = wrapped { expects :timestamp, type: DateTime }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:timestamp][:type]).to eq("string")
        expect(properties[:timestamp][:format]).to eq("date-time")
      end

      it "maps Time to string with date-time format" do
        tool = wrapped { expects :created_at, type: Time }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:created_at][:type]).to eq("string")
        expect(properties[:created_at][:format]).to eq("date-time")
      end

      # NOTE: TrueClass/FalseClass gain an explicit enum (core's TypeValidator only accepts the
      # singleton value, so a bare "boolean" type would wrongly let a client send the other value too).
      it "maps TrueClass to boolean with a true-only enum" do
        tool = wrapped { expects :flag, type: TrueClass }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:flag][:type]).to eq("boolean")
        expect(properties[:flag][:enum]).to eq([true])
      end

      it "maps FalseClass to boolean with a false-only enum" do
        tool = wrapped { expects :flag, type: FalseClass }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:flag][:type]).to eq("boolean")
        expect(properties[:flag][:enum]).to eq([false])
      end

      it "handles type in hash format" do
        tool = wrapped { expects :count, type: { klass: Integer } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:count][:type]).to eq("integer")
      end

      it "falls back to string for unknown types on input" do
        custom_class = Class.new
        tool = wrapped { expects :custom, type: custom_class }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:custom][:type]).to eq("string")
      end
    end

    describe "required/optional/nullable" do
      it "marks required fields in required array" do
        tool = wrapped { expects :name, type: String }
        expect(tool.input_schema_value.to_h[:required]).to include("name")
      end

      # A nullable field now reflects as a `type` ARRAY (e.g. ["string", "null"]) rather than a bare
      # type -- core adds "null" to the JSON type whenever the field's validators tolerate nil/blank.
      it "excludes optional fields from required array and reflects nullability as a type array" do
        tool = wrapped { expects :name, type: String, optional: true }
        schema = tool.input_schema_value.to_h
        expect(schema[:required]).to be_nil
        expect(schema[:properties][:name][:type]).to eq(%w[string null])
      end

      it "excludes fields with allow_blank from required array and reflects nullability as a type array" do
        tool = wrapped { expects :name, type: String, allow_blank: true }
        schema = tool.input_schema_value.to_h
        expect(schema[:required]).to be_nil
        expect(schema[:properties][:name][:type]).to eq(%w[string null])
      end

      it "does not include server_context in input schema" do
        tool = wrapped { expects :name, type: String }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties).to have_key(:name)
        expect(properties).not_to have_key(:server_context)
      end
    end

    describe "defaults" do
      it "includes default values in schema" do
        tool = wrapped { expects :status, type: String, default: "pending" }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:status][:default]).to eq("pending")
      end

      it "omits default when not provided" do
        tool = wrapped { expects :name, type: String }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:name]).not_to have_key(:default)
      end
    end

    describe "descriptions" do
      # Pass description: directly as a kwarg -- NOT metadata: { description: "..." }.
      # The metadata: hash is not a recognized key and raises ArgumentError.
      it "includes description: kwarg in schema" do
        tool = wrapped { expects :name, type: String, description: "The user's full name" }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:name][:description]).to eq("The user's full name")
      end

      it "omits description when not provided" do
        tool = wrapped { expects :name, type: String }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:name]).not_to have_key(:description)
      end

      it "raises ArgumentError when metadata: hash is passed instead of description: kwarg" do
        expect do
          wrapped { expects :name, type: String, metadata: { description: "The user's full name" } }
        end.to raise_error(ArgumentError, /metadata/)
      end
    end

    describe "enum from inclusion" do
      it "extracts enum from inclusion :in" do
        tool = wrapped { expects :status, inclusion: { in: %w[active inactive pending] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:status][:enum]).to eq(%w[active inactive pending])
      end

      it "extracts enum from inclusion :within" do
        tool = wrapped { expects :priority, inclusion: { within: [1, 2, 3] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:priority][:enum]).to eq([1, 2, 3])
      end

      it "infers type from enum values" do
        tool = wrapped { expects :status, inclusion: { in: %w[active inactive] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:status][:type]).to eq("string")
      end

      it "infers integer type from integer enum values" do
        tool = wrapped { expects :priority, inclusion: { in: [1, 2, 3] } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:priority][:type]).to eq("integer")
      end

      it "infers number type from float enum values" do
        tool = wrapped { expects :rate, inclusion: { in: [0.5, 1.0, 1.5] } }
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
        tool = wrapped { expects :user, model: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties).to have_key(:user_id)
        expect(properties).not_to have_key(:user)
      end

      # NOTE: core does NOT constrain the generated id field's JSON type (the old builder hard-coded
      # "integer") -- a model's primary key isn't knowable from the declaration (could be a UUID,
      # string, etc.) and inferring it would require a DB load, so it's left untyped. A required
      # model id also gets `not: { type: "null" }` since a null token can't resolve to a record.
      it "leaves the generated id field's type unconstrained but non-null when required" do
        tool = wrapped { expects :user, model: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user_id]).not_to have_key(:type)
        expect(properties[:user_id][:not]).to eq({ type: "null" })
      end

      it "auto-generates description for model field" do
        tool = wrapped { expects :user, model: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user_id][:description]).to eq("ID of the User record")
      end

      it "allows custom description to override auto-generated" do
        tool = wrapped { expects :user, model: true, description: "The target user's ID" }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user_id][:description]).to eq("The target user's ID")
      end

      it "marks model id field as required when model field is required" do
        tool = wrapped { expects :user, model: true }
        expect(tool.input_schema_value.to_h[:required]).to include("user_id")
      end
    end

    describe "subfield handling" do
      it "nests subfields under parent object" do
        tool = wrapped do
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
        tool = wrapped do
          expects :user, type: Hash
          expects :email, on: :user, type: String
          expects :nickname, on: :user, type: String, optional: true
        end
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:user][:required]).to include("email")
        expect(properties[:user][:required]).not_to include("nickname")
      end

      it "omits nested required array when all subfields are optional" do
        tool = wrapped do
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
        tool = wrapped { expects :count, numericality: { only_integer: true } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:count][:type]).to eq("integer")
      end

      it "infers number from numericality without only_integer" do
        tool = wrapped { expects :amount, numericality: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:amount][:type]).to eq("number")
      end

      it "infers number from numericality hash without only_integer" do
        tool = wrapped { expects :value, numericality: { greater_than: 0 } }
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
        tool = wrapped { expects :name, presence: true }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:name]).not_to have_key(:type)
      end

      it "returns empty type info for a length-only field" do
        tool = wrapped { expects :code, length: { minimum: 3, maximum: 10 } }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:code]).not_to have_key(:type)
      end
    end

    describe "fields with no type inference" do
      it "returns empty type info when no type can be inferred" do
        tool = wrapped { expects :unknown, optional: true }
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
          tool = wrapped { expects :tags, type: Array, of: ruby_type }
          properties = tool.input_schema_value.to_h[:properties]
          expect(properties[:tags][:items]).to eq(expected_items)
        end
      end

      it "does not emit items for plain Array without of:" do
        tool = wrapped { expects :things, type: Array }
        properties = tool.input_schema_value.to_h[:properties]
        expect(properties[:things]).not_to have_key(:items)
      end
    end

    describe "shape: block schema (works on input regardless of of:)" do
      it "emits items.properties with typed members for an Array field with shape: (no of:)" do
        tool = wrapped do
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
        tool = wrapped do
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
        tool = wrapped do
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
      tool = wrapped do
        exposes :output, type: String, description: "The output"
      end

      schema = tool.output_schema
      expect(schema).to be_a(MCP::Tool::OutputSchema)
      expect(schema.to_h[:properties][:output][:type]).to eq("string")
    end

    it "returns nil when no exposes" do
      tool = wrapped do
        expects :name, type: String
      end

      expect(tool.output_schema).to be_nil
    end

    describe "basic output shape" do
      it "builds schema from external field configs" do
        tool = wrapped do
          exposes :output, type: String
          exposes :count, type: Integer
        end
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:output][:type]).to eq("string")
        expect(properties[:count][:type]).to eq("integer")
      end

      it "includes descriptions" do
        tool = wrapped { exposes :output, type: String, description: "The computed result" }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:output][:description]).to eq("The computed result")
      end

      it "falls back to untyped for unknown types on output" do
        # NOTE: differs from the old builder, which fell back to type: "object". Core cannot prove an
        # arbitrary class's serialized wire shape (its as_json/to_h could emit a scalar, array, or
        # differently-shaped hash), so it leaves the property untyped rather than assert "object" the
        # serialized value might contradict (see single_type_for's "Unknown class" comment).
        custom_class = Class.new
        tool = wrapped { exposes :custom, type: custom_class }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:custom]).not_to have_key(:type)
      end

      it "marks every exposed field required (JSON Schema `required` means presence, not non-null) and reflects optionality as nullability" do
        # NOTE: differs from the old builder, which omitted optional fields from `required`. Every
        # exposes key is always present in the serialized output (nil when unset), so JSON Schema
        # `required` (property PRESENCE) is always true; the optional field's OPTIONALITY instead shows
        # up as a nullable type.
        tool = wrapped do
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
          tool = wrapped { exposes :tags, type: Array, of: ruby_type }
          properties = tool.output_schema_value.to_h[:properties]
          expect(properties[:tags][:items]).to eq(expected_items)
        end
      end

      # NOTE: differs from the old builder, which mapped of: Numeric to items: { type: "number" } on
      # output too. Core leaves a Numeric-typed output element untyped: `Numeric` admits a `Complex`
      # value, whose serialized wire form (a JSON number vs. a String via to_s) isn't knowable from the
      # declaration alone, so it's left untyped rather than assert "number" (see single_type_for).
      it "omits items entirely for of: Numeric (Numeric admits Complex, unknowable on output)" do
        tool = wrapped { exposes :tags, type: Array, of: Numeric }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:tags]).not_to have_key(:items)
      end

      it "emits items { type: 'boolean' } for of: :boolean" do
        tool = wrapped { exposes :flags, type: Array, of: :boolean }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:flags][:items]).to eq({ type: "boolean" })
      end

      it "emits items { type: 'string', format: 'uuid' } for of: :uuid" do
        tool = wrapped { exposes :ids, type: Array, of: :uuid }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:ids][:items]).to eq({ type: "string", format: "uuid" })
      end

      it "emits items { anyOf: [...] } for a union of: [String, Numeric], leaving the Numeric member untyped" do
        # NOTE: the Numeric member is `{}` rather than `{ type: "number" }` -- same Complex-admitting
        # rationale as the standalone of: Numeric case above.
        tool = wrapped { exposes :values, type: Array, of: [String, Numeric] }
        properties = tool.output_schema_value.to_h[:properties]
        expect(properties[:values][:items]).to eq({ anyOf: [{ type: "string" }, {}] })
      end

      it "emits items with bare member properties for of: <Data.define subclass>" do
        record_klass = Data.define(:source, :status, :active)
        tool = wrapped { exposes :records, type: Array, of: record_klass }
        items = tool.output_schema_value.to_h[:properties][:records][:items]
        expect(items[:type]).to eq("object")
        expect(items[:properties].keys).to contain_exactly(:source, :status, :active)
        expect(items[:properties][:source]).to eq({})
      end

      it "does not emit items for plain Array without of:" do
        tool = wrapped { exposes :things, type: Array }
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
        tool = wrapped do
          exposes :entries, type: Array do
            field :name, type: String
            field :count, type: Integer
          end
        end
        properties = tool.output_schema_value.to_h[:properties]
        # No `items` overlay (the point of this spec); `minItems: 1` is axn core reflecting the
        # required field's non-blank presence validation, orthogonal to the shape/of: question.
        expect(properties[:entries]).to eq({ type: "array", minItems: 1 })
      end

      it "emits properties directly on a Hash field's shape: block" do
        tool = wrapped do
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
        tool = wrapped do
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
        tool = wrapped do
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
        tool = wrapped do
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
        tool = wrapped do
          exposes :records, type: Array, of: record_klass do
            field :source, type: String
          end
        end
        items = tool.output_schema_value.to_h[:properties][:records][:items]
        expect(items[:properties].keys).to include(:source, :status, :active)
      end
    end
  end

  describe ".input_schema_value" do
    it "returns the same object as input_schema" do
      tool = wrapped do
        expects :name, type: String
      end

      expect(tool.input_schema_value).to eq(tool.input_schema)
    end
  end

  describe ".output_schema_value" do
    it "returns nil when no exposes" do
      tool = wrapped do
        expects :name, type: String
      end

      expect(tool.output_schema_value).to be_nil
    end

    it "returns the same object as output_schema when exposes exist" do
      tool = wrapped do
        exposes :output, type: String
      end

      expect(tool.output_schema_value).to eq(tool.output_schema)
    end
  end

  describe ".to_h" do
    it "includes auto-generated schemas in MCP format" do
      axn = Class.new { include Axn }
      axn.class_eval do
        expects :name, type: String
        exposes :greeting, type: String
      end
      tool = Axn::MCP.wrap(axn, name: "test_tool", description: "A test tool")

      hash = tool.to_h
      expect(hash[:description]).to eq("A test tool")
      expect(hash[:inputSchema]).to be_a(Hash)
      expect(hash[:inputSchema][:properties][:name][:type]).to eq("string")
      expect(hash[:outputSchema][:properties][:greeting][:type]).to eq("string")
    end
  end
end
