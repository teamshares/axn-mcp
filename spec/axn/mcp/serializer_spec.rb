# frozen_string_literal: true

RSpec.describe Axn::MCP::Serializer do
  describe ".serialize_value" do
    it "passes through nil" do
      expect(described_class.serialize_value(nil)).to be_nil
    end

    it "passes through strings" do
      expect(described_class.serialize_value("hello")).to eq("hello")
    end

    it "passes through integers" do
      expect(described_class.serialize_value(42)).to eq(42)
    end

    it "passes through floats" do
      expect(described_class.serialize_value(3.14)).to eq(3.14)
    end

    it "passes through booleans" do
      expect(described_class.serialize_value(true)).to be true
      expect(described_class.serialize_value(false)).to be false
    end

    it "recursively serializes hashes" do
      input = { a: 1, b: { c: 2 } }
      expected = { "a" => 1, "b" => { "c" => 2 } }
      expect(described_class.serialize_value(input)).to eq(expected)
    end

    it "recursively serializes arrays" do
      input = [1, { a: 2 }, [3, 4]]
      expected = [1, { "a" => 2 }, [3, 4]]
      expect(described_class.serialize_value(input)).to eq(expected)
    end

    it "calls as_json on objects that respond to it" do
      obj = double("model", as_json: { "id" => 1, "name" => "Test" })
      expect(described_class.serialize_value(obj)).to eq({ "id" => 1, "name" => "Test" })
    end

    it "calls to_h on objects that respond to it but not as_json" do
      obj = Struct.new(:a, :b).new(1, 2)
      allow(obj).to receive(:respond_to?).with(:as_json).and_return(false)
      allow(obj).to receive(:respond_to?).with(:to_h).and_return(true)
      result = described_class.serialize_value(obj)
      expect(result).to eq({ "a" => 1, "b" => 2 })
    end

    it "falls back to to_s for other objects" do
      obj = Object.new
      def obj.to_s
        "custom_string"
      end
      expect(described_class.serialize_value(obj)).to eq("custom_string")
    end
  end

  describe ".serialize_exposed" do
    it "serializes all exposed fields from result" do
      tool = Class.new(Axn::MCP::Tool) do
        exposes :name, type: String
        exposes :count, type: Integer

        def call
          expose name: "test", count: 42
        end
      end

      tool.call
      # We need to test the serialization directly
      configs = tool.external_field_configs

      # Create a mock result with the exposed values
      mock_result = double("result")
      allow(mock_result).to receive(:public_send).with(:name).and_return("test")
      allow(mock_result).to receive(:public_send).with(:count).and_return(42)

      serialized = described_class.serialize_exposed(mock_result, configs)
      expect(serialized).to eq({ "name" => "test", "count" => 42 })
    end
  end

  describe ".result_to_mcp_response" do
    let(:field_configs) { [] }

    context "when success with exposed data and text_content: :structured (default)" do
      it "uses JSON of structured content for text block" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :greeting, type: String

          def call
            expose greeting: "Hi"
          end
        end
        result = tool.call
        configs = tool.external_field_configs

        response = described_class.result_to_mcp_response(result, configs, text_content: :structured)

        expect(response.content.first[:text]).to eq('{"greeting":"Hi"}')
        expect(response.structured_content).to eq({ "greeting" => "Hi" })
        expect(response.error?).to be false
      end
    end

    context "when success with no exposed data" do
      it "uses result.success/message for text block" do
        tool = Class.new(Axn::MCP::Tool) do
          success "Done!"

          def call
            # no exposes
          end
        end
        result = tool.call

        response = described_class.result_to_mcp_response(result, [], text_content: :structured)

        expect(response.content.first[:text]).to eq("Done!")
        expect(response.error?).to be false
      end
    end

    context "when success with text_content: :message and exposed data" do
      it "uses result.success for text block" do
        tool = Class.new(Axn::MCP::Tool) do
          exposes :greeting, type: String
          success "Custom message"

          def call
            expose greeting: "Hi"
          end
        end
        result = tool.call
        configs = tool.external_field_configs

        response = described_class.result_to_mcp_response(result, configs, text_content: :message)

        expect(response.content.first[:text]).to eq("Custom message")
        expect(response.structured_content).to eq({ "greeting" => "Hi" })
      end
    end

    context "when error" do
      it "uses result.error for text and sets error: true" do
        tool = Class.new(Axn::MCP::Tool) do
          def call
            fail! "Something went wrong"
          end
        end
        result = tool.call

        response = described_class.result_to_mcp_response(result, [], text_content: :structured)

        expect(response.content.first[:text]).to eq("Something went wrong")
        expect(response.error?).to be true
      end
    end
  end
end
