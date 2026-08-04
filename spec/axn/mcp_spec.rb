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

  describe "Error" do
    it "is a StandardError subclass" do
      expect(Axn::MCP::Error).to be < StandardError
    end

    it "declares core's Axn::Error public-error boundary, so `rescue Axn::Error` catches it (PRO-2997)" do
      expect(Axn::MCP::Error).to be < Axn::Error
      expect { raise Axn::MCP::Error, "boom" }.to raise_error(Axn::Error)
    end
  end

  describe "SchemaError" do
    it "is an Axn::MCP::Error (and thus a StandardError) subclass" do
      expect(Axn::MCP::SchemaError).to be < Axn::MCP::Error
      expect(Axn::MCP::SchemaError).to be < StandardError
    end

    it "is caught by `rescue Axn::Error`" do
      expect { raise Axn::MCP::SchemaError, "Invalid schema" }
        .to raise_error(Axn::Error, "Invalid schema")
    end

    it "can be raised with a message" do
      expect { raise Axn::MCP::SchemaError, "Invalid schema" }
        .to raise_error(Axn::MCP::SchemaError, "Invalid schema")
    end
  end
end
