# frozen_string_literal: true

require "json"

# Axn core renders every `input_schema_residues` entry into the `description` at its path, so this adapter
# must carry `input_schema` to an MCP client unchanged rather than render residues itself. These examples
# read what a client receives (the `tools/list` response) and compare it with core's `input_schema`, so
# every adapter that equals core also equals every other adapter.
RSpec.describe "Input schema residue descriptions over MCP", type: :integration do
  # The MCP SDK prepends the 2020-12 dialect URI to every input schema that lacks one (MCP mandates that
  # dialect); it is the only key the transport adds.
  let(:dialect) { "https://json-schema.org/draft/2020-12/schema" }

  let(:lookup_model) { Struct.new(:id) { def self.find(id) = id == 1 ? new(id) : nil } }

  def listed_input_schema(axn_class)
    server = MCP::Server.new(name: "test_server", version: "1.0.0", tools: [Axn::MCP.wrap(axn_class)])
    response = JSON.parse(server.handle_json({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json))
    response.dig("result", "tools", 0, "inputSchema")
  end

  def core_input_schema(axn_class)
    JSON.parse(JSON.generate(axn_class.input_schema))
  end

  # Every `description` in the document, keyed by its full JSON path, so a nested or array-item
  # description is compared as well as a top-level one.
  def descriptions(node, path = [], found = {})
    case node
    when Hash
      found[path] = node["description"] if node.key?("description")
      node.each { |key, child| descriptions(child, path + [key], found) }
    when Array
      node.each_with_index { |child, index| descriptions(child, path + [index], found) }
    end
    found
  end

  def property_path(residue_path)
    residue_path.flat_map { |segment| ["properties", segment.to_s] }
  end

  context "with residues at the top level and nested" do
    let(:axn_class) do
      model = lookup_model
      Class.new do
        include Axn

        def self.name = "ResidueFixture"

        description "Fixture whose contract JSON Schema cannot state in full"
        expects :code, type: String, description: "Two-letter code — e.g. “US”", length: { is: 2 }, if: -> { true }
        expects :slug, type: String, format: { with: /\A[a-z]+\z/i }
        expects :meta, type: Hash
        expects :count, on: :meta, type: Integer, description: "A count", numericality: { greater_than: 0 }, if: -> { true }
        expects :company, model: { klass: model, finder: :find, id_type: Integer }
        expects :scores, type: Array, of: Float, optional: true

        def call; end
      end
    end

    it "has residues at every path the examples below depend on" do
      expect(axn_class.input_schema_residues.map(&:path).uniq).to contain_exactly(%i[code], %i[slug], %i[meta count], %i[company_id], %i[scores])
    end

    # A residue on an array's elements is described on its `items`, inside the property the residue names.
    it "delivers each residue's summary in a listed description under its property" do
      listed = descriptions(listed_input_schema(axn_class))

      axn_class.input_schema_residues.each do |residue|
        prefix = property_path(residue.path)
        under = listed.select { |path, _| path.first(prefix.size) == prefix }.values
        expect(under).to include(a_string_including(residue.summary))
      end
    end

    it "lists every description exactly as core's input_schema states it" do
      core = descriptions(core_input_schema(axn_class))

      expect(core.keys).to include(property_path(%i[meta count]), property_path(%i[scores]) + ["items"])
      expect(descriptions(listed_input_schema(axn_class))).to eq(core)
    end

    it "lists core's input_schema unchanged apart from the dialect URI" do
      listed = listed_input_schema(axn_class)

      expect(listed["$schema"]).to eq(dialect)
      expect(JSON.generate(listed.except("$schema"))).to eq(JSON.generate(core_input_schema(axn_class)))
    end
  end

  context "without residues" do
    let(:axn_class) do
      Class.new do
        include Axn

        def self.name = "PlainFixture"

        expects :name, type: String, description: "The user's name"
        expects :limit, type: Integer, optional: true, numericality: { greater_than: 0 }

        def call; end
      end
    end

    it "lists core's input_schema unchanged apart from the dialect URI" do
      expect(axn_class.input_schema_residues).to be_empty

      listed = listed_input_schema(axn_class)

      expect(listed.keys.first).to eq("$schema")
      expect(listed["$schema"]).to eq(dialect)
      expect(JSON.generate(listed.except("$schema"))).to eq(JSON.generate(core_input_schema(axn_class)))
    end
  end
end
