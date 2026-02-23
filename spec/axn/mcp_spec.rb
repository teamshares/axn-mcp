# frozen_string_literal: true

RSpec.describe Axn::MCP do
  describe "VERSION" do
    it "is defined" do
      expect(Axn::MCP::VERSION).to be_a(String)
    end

    it "follows semantic versioning format" do
      expect(Axn::MCP::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe "SchemaError" do
    it "is a StandardError subclass" do
      expect(Axn::MCP::SchemaError).to be < StandardError
    end

    it "can be raised with a message" do
      expect { raise Axn::MCP::SchemaError, "Invalid schema" }
        .to raise_error(Axn::MCP::SchemaError, "Invalid schema")
    end
  end
end
