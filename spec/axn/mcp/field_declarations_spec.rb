# frozen_string_literal: true

RSpec.describe Axn::MCP::FieldDeclarations do
  describe ".hydrate" do
    it "returns hash as-is" do
      input = { name: { type: String }, age: { type: Integer } }
      expect(described_class.hydrate(input)).to eq(input)
    end

    it "converts array of symbols to hash with empty options" do
      input = %i[name age]
      expect(described_class.hydrate(input)).to eq({ name: {}, age: {} })
    end

    it "converts array of hashes to merged hash" do
      input = [{ name: { type: String } }, { age: { type: Integer } }]
      expect(described_class.hydrate(input)).to eq({ name: { type: String }, age: { type: Integer } })
    end

    it "handles mixed array of symbols and hashes" do
      input = [:name, { age: { type: Integer } }, :email]
      expect(described_class.hydrate(input)).to eq({ name: {}, age: { type: Integer }, email: {} })
    end

    it "handles empty array" do
      expect(described_class.hydrate([])).to eq({})
    end

    it "handles single symbol wrapped in array" do
      expect(described_class.hydrate([:name])).to eq({ name: {} })
    end
  end
end
