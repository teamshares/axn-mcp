# frozen_string_literal: true

RSpec.describe Axn::MCP::Serializer do
  describe ".result_to_mcp_response" do
    it "serializes exposed values through Axn::Extensions::Serialization.render" do
      tool = Class.new do
        include Axn

        exposes :count, type: Integer

        def call = expose(count: 42)
      end
      result = tool.call

      response = described_class.result_to_mcp_response(result, text_content: :structured)

      expect(response.structured_content).to eq(Axn::Extensions::Serialization.render(result))
    end

    context "when success with exposed data and text_content: :structured (default)" do
      it "uses JSON of structured content for text block" do
        tool = Class.new do
          include Axn

          exposes :greeting, type: String

          def call
            expose greeting: "Hi"
          end
        end
        result = tool.call

        response = described_class.result_to_mcp_response(result, text_content: :structured)

        expect(response.content.first[:text]).to eq('{"greeting":"Hi"}')
        expect(response.structured_content).to eq({ "greeting" => "Hi" })
        expect(response.error?).to be false
      end
    end

    context "when success with no exposed data" do
      it "uses result.success/message for text block" do
        tool = Class.new do
          include Axn

          success "Done!"

          def call
            # no exposes
          end
        end
        result = tool.call

        response = described_class.result_to_mcp_response(result, text_content: :structured)

        expect(response.content.first[:text]).to eq("Done!")
        expect(response.error?).to be false
      end
    end

    context "when success with text_content: :message and exposed data" do
      it "uses result.success for text block" do
        tool = Class.new do
          include Axn

          exposes :greeting, type: String
          success "Custom message"

          def call
            expose greeting: "Hi"
          end
        end
        result = tool.call

        response = described_class.result_to_mcp_response(result, text_content: :message)

        expect(response.content.first[:text]).to eq("Custom message")
        expect(response.structured_content).to eq({ "greeting" => "Hi" })
      end
    end

    context "with an opaque exposed value (one with no author-declared JSON rendering)" do
      let(:opaque_tool) do
        Class.new do
          include Axn

          exposes :obj

          def call = expose(obj: Object.new)
        end
      end

      it "ships the opaque rendering by default (reject_opaque_exposed_values omitted)" do
        result = opaque_tool.call

        response = described_class.result_to_mcp_response(result, text_content: :structured)

        expect(response.error?).to be false
        expect(response.structured_content["obj"]).to match(/\A#<Object:0x/)
      end

      it "raises Axn::Reflection::UnserializableValue when reject_opaque_exposed_values: true" do
        result = opaque_tool.call

        expect do
          described_class.result_to_mcp_response(result, text_content: :structured, reject_opaque_exposed_values: true)
        end.to raise_error(Axn::Reflection::UnserializableValue, /obj/)
      end
    end

    context "when error" do
      it "uses result.error for text and sets error: true" do
        tool = Class.new do
          include Axn

          def call
            fail! "email taken"
          end
        end
        result = tool.call

        response = described_class.result_to_mcp_response(result, text_content: :structured)

        expect(response.content.first[:text]).to eq("email taken")
        expect(response.error?).to be true
      end
    end
  end
end
