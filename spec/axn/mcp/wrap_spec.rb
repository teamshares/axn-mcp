# frozen_string_literal: true

RSpec.describe "Axn::MCP.wrap" do
  let(:plain_axn) do
    Class.new do
      include Axn

      def self.name = "GreetPlainly"

      expects :name, type: String
      expects :user_id, on: :ambient_context, type: Object, optional: true # spread from server_context
      exposes :greeting, type: String

      def call
        expose greeting: "Hello, #{name}! (user #{user_id.inspect})"
      end
    end
  end

  it "proves author-once: the original Axn is untouched and still returns Axn::Result directly" do
    result = plain_axn.call(name: "Alice")

    expect(result).to be_a(Axn::Result)
    expect(result).to be_ok
    expect(result.greeting).to eq("Hello, Alice! (user nil)")
  end

  it "wraps a plain Axn as an ::MCP::Tool subclass" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

    expect(tool).to be < MCP::Tool
    expect(tool.description).to eq("Greets someone")
    expect(tool.input_schema_value.to_h[:properties]).to have_key(:name)
    expect(tool.input_schema_value.to_h[:properties]).not_to have_key(:server_context)
  end

  it "maps server_context into the wrapped Axn's ambient_context" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

    response = tool.call(name: "Bob", server_context: { user_id: 42 })

    expect(response).to be_a(MCP::Tool::Response)
    expect(JSON.parse(response.content.first[:text])["greeting"]).to eq("Hello, Bob! (user 42)")
  end

  it "sets annotations from the wrap kwarg" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone", annotations: { read_only_hint: true })

    expect(tool.annotations_value.read_only_hint).to be true
  end

  describe "per-tool MCP metadata declarable via configure(:mcp) (survives the zero-arg Axn::MCP.tools path)" do
    let(:configured_axn) do
      Class.new do
        include Axn

        def self.name = "ConfiguredMetadataAxn"
        exposes :x, type: String
        def call = expose(x: "y")

        configure(:mcp) do |c|
          c.title = "Configured Title"
          c.icons = [{ src: "https://example.com/i.png" }]
          c.meta = { version: "9" }
          c.annotations = { read_only_hint: true }
        end
      end
    end

    it "applies title/icons/meta/annotations from configure(:mcp) at wrap time (no wrap kwargs needed)" do
      tool = Axn::MCP.wrap(configured_axn)

      expect(tool.title).to eq("Configured Title")
      expect(tool.icons).to eq([{ src: "https://example.com/i.png" }])
      expect(tool.meta).to eq({ version: "9" })
      expect(tool.annotations_value.read_only_hint).to be true
    end

    it "lets an explicit wrap kwarg win over the configure(:mcp) value" do
      tool = Axn::MCP.wrap(configured_axn, title: "Override Title")

      expect(tool.title).to eq("Override Title")
    end
  end

  describe "annotations derived from the wrapped Axn's semantic_hints" do
    def wrap_with_hints(*hints, **wrap_opts)
      axn = Class.new do
        include Axn

        def self.name = "HintedAxn"
        exposes :x, type: String
        def call = expose(x: "y")
      end
      axn.semantic_hints(*hints)
      Axn::MCP.wrap(axn, description: "d", **wrap_opts)
    end

    it "maps semantic_hints to MCP annotations (read_only also asserts destructive_hint: false)" do
      annotations = wrap_with_hints(:read_only, :closed_world).annotations_value

      expect(annotations.read_only_hint).to be true
      expect(annotations.destructive_hint).to be false
      expect(annotations.open_world_hint).to be false
    end

    it "leaves annotations unset when the Axn declares no hints" do
      expect(wrap_with_hints.annotations_value).to be_nil
    end

    it "lets an explicit annotations: kwarg win over hint-derived defaults" do
      annotations = wrap_with_hints(:read_only, annotations: { destructive_hint: true }).annotations_value

      expect(annotations.destructive_hint).to be true
      expect(annotations.read_only_hint).to be_falsey # explicit hash replaces the hint-derived set wholesale
    end
  end

  it "sets title/icons/meta from the wrap kwargs, mirroring annotations:" do
    tool = Axn::MCP.wrap(
      plain_axn,
      description: "Greets someone",
      title: "Greeter",
      icons: [{ src: "https://example.com/icon.png" }],
      meta: { version: "1.0" },
    )

    expect(tool.title).to eq("Greeter")
    expect(tool.icons).to eq([{ src: "https://example.com/icon.png" }])
    expect(tool.meta).to eq({ version: "1.0" })
  end

  it "leaves title/icons/meta unset (matching MCP::Tool's own defaults) when not passed to wrap" do
    tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

    expect(tool.title).to be_nil
    expect(tool.icons).to be_nil
    expect(tool.meta).to be_nil
  end

  describe "tool naming" do
    it "derives a usable MCP tool name from the wrapped Axn's own class name when name: isn't given" do
      # Simulates the real gap: passing wrap's return value straight into an array/inline usage,
      # never assigning it to a constant (which would otherwise give the anonymous class a name).
      tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

      expect(tool.name_value).to eq("greet_plainly")
    end

    it "still honors an explicit name: over the derived default" do
      tool = Axn::MCP.wrap(plain_axn, description: "Greets someone", name: "custom_name")

      expect(tool.name_value).to eq("custom_name")
    end

    it "derives the name via axn core's tool_name, honoring a `tool name:` override on the wrapped Axn" do
      named = Class.new do
        include Axn

        def self.name = "SomeVerboseClassName"
        tool name: "concise"
        exposes :x, type: String
        def call = expose(x: "y")
      end

      tool = Axn::MCP.wrap(named, description: "d")

      expect(tool.name_value).to eq("concise")
    end

    it "uses axn core's tool_name verbatim, so the same class yields the same name across adapter gems" do
      # Cross-gem parity guardrail (mirror of the same assertion in axn-ruby_llm, PRO-2924): both
      # Axn::MCP.wrap and Axn::RubyLLM.wrap derive the tool name from core's `tool_name`, so wrapping
      # the SAME Axn on either surface produces identical names. Pinning `== axn_class.tool_name` here
      # is the axn-mcp half of that contract.
      named = Class.new do
        include Axn

        def self.name = "SomeVerboseClassName"
        tool name: "concise"
        exposes :x, type: String
        def call = expose(x: "y")
      end

      expect(Axn::MCP.wrap(named, description: "d").name_value).to eq(named.tool_name)
      expect(Axn::MCP.wrap(plain_axn, description: "d").name_value).to eq(plain_axn.tool_name)
    end

    it "honors a per-adapter `tool mcp: { name: }` override over the shared/derived name (PRO-2942)" do
      named = Class.new do
        include Axn

        def self.name = "SomeVerboseClassName"
        tool mcp: { name: "mcp_specific" }
        exposes :x, type: String
        def call = expose(x: "y")
      end

      expect(Axn::MCP.wrap(named, description: "d").name_value).to eq("mcp_specific")
    end

    it "raises when neither name: nor a derivable axn_class.name is available" do
      truly_anonymous = Class.new do
        include Axn

        exposes :greeting, type: String
        def call = expose(greeting: "hi")
      end

      expect do
        Axn::MCP.wrap(truly_anonymous, description: "Greets someone")
      end.to raise_error(ArgumentError, /requires name:/)
    end
  end

  describe "description defaulting" do
    let(:described_axn) do
      Class.new do
        include Axn

        def self.name = "DescribedAxn"
        description "From the Axn itself"
        exposes :x, type: String
        def call = expose(x: "y")
      end
    end

    it "defaults description to the wrapped Axn's own .description when none is passed" do
      tool = Axn::MCP.wrap(described_axn)

      expect(tool.description).to eq("From the Axn itself")
    end

    it "still lets an explicit description: win over the Axn's own" do
      tool = Axn::MCP.wrap(described_axn, description: "Override")

      expect(tool.description).to eq("Override")
    end
  end

  describe "present_as resolution" do
    around do |example|
      original = Axn::MCP.config.present_as
      example.run
    ensure
      Axn::MCP.config.present_as = original
    end

    it "re-reads the gem-wide config fresh on every call, not just once at wrap-time" do
      Axn::MCP.config.present_as = :structured
      tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")

      structured_response = tool.call(name: "Alice", server_context: {})
      expect(JSON.parse(structured_response.content.first[:text])).to have_key("greeting")

      Axn::MCP.config.present_as = :message
      message_response = tool.call(name: "Alice", server_context: {})
      expect(message_response.content.first[:text]).to eq("Action completed successfully")
    end

    it "raises ArgumentError for an invalid present_as value, matching Axn::MCP.config's own validation" do
      expect do
        Axn::MCP.wrap(plain_axn, description: "Greets someone", present_as: :mesage)
      end.to raise_error(ArgumentError, "present_as must be one of :structured, :message; got :mesage")
    end

    it "raises ArgumentError for present_as: false rather than silently falling back to the default" do
      expect do
        Axn::MCP.wrap(plain_axn, description: "Greets someone", present_as: false)
      end.to raise_error(ArgumentError, "present_as must be one of :structured, :message; got false")
    end

    it "raises a pointed migration error for the retired `mcp_text_content:` kwarg (renamed to present_as:)" do
      expect do
        Axn::MCP.wrap(plain_axn, description: "Greets someone", mcp_text_content: :message)
      end.to raise_error(ArgumentError, /`mcp_text_content:` was renamed to `present_as:`.*Replace `mcp_text_content: :message` with `present_as: :message`/m)
    end

    it "honors the wrapped Axn's own per-action present_as override when wrap isn't given an explicit one" do
      Axn::MCP.config.present_as = :structured
      plain_axn.configure(:mcp) { |c| c.present_as = :message }

      tool = Axn::MCP.wrap(plain_axn, description: "Greets someone")
      response = tool.call(name: "Alice", server_context: {})

      expect(response.content.first[:text]).to eq("Action completed successfully")
    end

    it "still lets wrap's own present_as: kwarg win over the wrapped Axn's per-action override" do
      plain_axn.configure(:mcp) { |c| c.present_as = :message }

      tool = Axn::MCP.wrap(plain_axn, description: "Greets someone", present_as: :structured)
      response = tool.call(name: "Alice", server_context: {})

      expect(JSON.parse(response.content.first[:text])).to have_key("greeting")
    end
  end
end
