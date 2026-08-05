# frozen_string_literal: true

RSpec.describe Axn::MCP::Annotations do
  describe "registered vocabulary" do
    it "extends axn core's semantic hint registry with MCP-only hints" do
      expect(Axn::Extensions.config.registered_semantic_hints).to include(:open_world, :closed_world)
    end

    it "keeps axn core's built-in hints registered too" do
      expect(Axn::Extensions.config.registered_semantic_hints).to include(:read_only, :idempotent, :destructive)
    end
  end

  describe ".annotations_for" do
    it "maps read_only to read_only_hint: true and destructive_hint: false" do
      expect(described_class.annotations_for([:read_only])).to eq(read_only_hint: true, destructive_hint: false)
    end

    it "maps idempotent to idempotent_hint: true" do
      expect(described_class.annotations_for([:idempotent])).to eq(idempotent_hint: true)
    end

    it "maps destructive to destructive_hint: true" do
      expect(described_class.annotations_for([:destructive])).to eq(destructive_hint: true)
    end

    it "maps open_world to open_world_hint: true" do
      expect(described_class.annotations_for([:open_world])).to eq(open_world_hint: true)
    end

    it "maps closed_world to open_world_hint: false" do
      expect(described_class.annotations_for([:closed_world])).to eq(open_world_hint: false)
    end

    it "combines multiple hints into one hash" do
      expect(described_class.annotations_for(%i[read_only idempotent])).to eq(
        read_only_hint: true, destructive_hint: false, idempotent_hint: true,
      )
    end

    it "lets an explicit destructive hint override read_only's implied non-destructiveness when both are declared" do
      expect(described_class.annotations_for(%i[read_only destructive])).to eq(
        read_only_hint: true, destructive_hint: true,
      )
    end

    it "returns an empty hash for no hints" do
      expect(described_class.annotations_for([])).to eq({})
    end
  end
end
