# frozen_string_literal: true

RSpec.describe Axn::MCP::Serializer do
  describe ".result_to_mcp_response" do
    it "serializes exposed values the same way Axn::Reflection::Values does" do
      config = Struct.new(:field).new(:count)
      result = double(ok?: true, count: 42, message: "done")

      response = described_class.result_to_mcp_response(result, [config], text_content: :structured)

      expect(response.structured_content).to eq(Axn::Reflection::Values.serialize_exposed(result, [config]))
    end

    let(:field_configs) { [] }

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
        configs = tool.external_field_configs

        response = described_class.result_to_mcp_response(result, configs, text_content: :structured)

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

        response = described_class.result_to_mcp_response(result, [], text_content: :structured)

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
        configs = tool.external_field_configs

        response = described_class.result_to_mcp_response(result, configs, text_content: :message)

        expect(response.content.first[:text]).to eq("Custom message")
        expect(response.structured_content).to eq({ "greeting" => "Hi" })
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

        response = described_class.result_to_mcp_response(result, [], text_content: :structured)

        expect(response.content.first[:text]).to eq("email taken")
        expect(response.error?).to be true
      end
    end
  end
end
