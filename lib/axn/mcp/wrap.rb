# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module Axn
  module MCP
    class << self
      # Exposes any Axn (whether or not it subclasses Axn::MCP::Tool) as an ::MCP::Tool subclass.
      # The wrapped class's own .call/.call! are untouched -- direct callers keep getting a plain
      # Axn::Result. All MCP transport concerns (schema, server_context routing, response mapping)
      # live entirely on the generated subclass, via the same Axn::MCP::Invocation path
      # Axn::MCP::Tool#call uses -- proves the "author once" story from PRO-2844/PRO-2842.
      #
      # The generated subclass is MCP-transport-only, unlike Axn::MCP::Tool: its .call always
      # returns MCP::Tool::Response (never a raw Axn::Result), and it deliberately has no .call! --
      # MCP::Server itself only ever calls .call, and a consumer wanting real bang/raise-on-failure
      # semantics can call the original wrapped class's own .call! directly (unwrapped).
      VALID_PRESENT_AS = %i[structured message].freeze

      # `server_context` is the input name the wrapper reserves for the injected MCP context
      # (Invocation strips it before calling the Axn), so a wrapped Axn must not declare it as a
      # top-level `expects`. (`ambient_context`, the other stripped key, needs no entry here: axn core
      # already reserves it and rejects `expects :ambient_context` at declaration.)
      RESERVED_INPUT_FIELDS = %i[server_context].freeze
      private_constant :RESERVED_INPUT_FIELDS

      # Sentinel for the retired `mcp_text_content:` kwarg (renamed to `present_as:`, PRO-2923), so a
      # caller still passing it gets a pointed migration error instead of silently having it ignored.
      RENAMED_MCP_TEXT_CONTENT = Object.new.freeze
      private_constant :RENAMED_MCP_TEXT_CONTENT

      # The gem-level convenience for building a ready-to-register MCP tool list (PRO-2923),
      # symmetric with `Axn::RubyLLM.tools`: enumerate every Axn that belongs to the :mcp adapter
      # (via axn core's process-global registry) and wrap each one. Zero-arg by design -- per-tool
      # customization comes from each class's own `configure(:mcp) { ... }` (honored inside `wrap`)
      # and its `tool name:`/`description`, not per-call kwargs -- so a consumer registers tools with
      # just `MCP::Server.new(tools: Axn::MCP.tools, ...)` instead of a hand-maintained array.
      def tools
        Axn::Tools.for(:mcp).map { |axn_class| wrap(axn_class) }
      end

      def wrap(axn_class, description: nil, name: nil, title: nil, icons: nil, meta: nil, annotations: nil,
               present_as: nil, mcp_text_content: RENAMED_MCP_TEXT_CONTENT)
        reject_renamed_mcp_text_content!(mcp_text_content)
        validate_present_as!(present_as)
        reject_reserved_input_fields!(axn_class)
        resolved_name = resolve_wrap_tool_name(axn_class, name)
        resolved_description = description || axn_class.description

        # Each metadata kwarg falls back to the wrapped Axn's own `configure(:mcp)` value (via axn
        # core's shadow-proof resolver), so it's carried through the zero-arg `Axn::MCP.tools` path
        # too; an explicit `wrap` kwarg still wins. `annotations` also falls back further, to the
        # `semantic_hints`-derived defaults -- precedence: kwarg > configure(:mcp) > semantic_hints.
        resolved_title = title || Axn::MCP.resolve_override_for(axn_class, :title)
        resolved_icons = icons || Axn::MCP.resolve_override_for(axn_class, :icons)
        resolved_meta  = meta  || Axn::MCP.resolve_override_for(axn_class, :meta)
        configured_annotations = annotations || Axn::MCP.resolve_override_for(axn_class, :annotations)

        # Surface the resolved revision in `_meta` (never the name -- name is the cross-adapter
        # identity), so an operator/model can see which version `Axn::MCP.tools` collapsed to. Only
        # for actually-versioned tools; an unversioned tool (default `tool_version` 1) stays
        # meta-free. Keyed `tool_version` to mirror the DSL and avoid clobbering a consumer's own
        # `version` meta key.
        resolved_meta = { **(resolved_meta || {}), tool_version: axn_class.tool_version } if axn_class.tool_version > 1

        Class.new(::MCP::Tool) do
          tool_name(resolved_name)
          description(resolved_description)
          title(resolved_title) if resolved_title
          icons(resolved_icons) if resolved_icons
          meta(resolved_meta) if resolved_meta

          # axn_class.input_schema/.output_schema are axn core's own public reflection entry points --
          # wiring to those directly, rather than reaching past them for the lower-level builder the
          # wrapped Axn's own methods already call, keeps this on the documented surface.
          input_schema(axn_class.input_schema)
          output_schema(axn_class.output_schema) unless axn_class.external_field_configs.empty?

          hint_annotations = Axn::MCP::Annotations.annotations_for(axn_class._semantic_hints)
          resolved_annotations = configured_annotations || (hint_annotations if hint_annotations.any?)
          # Skip the setter for an EMPTY hash, not just nil: `annotations: {}` (or a `configure(:mcp)`
          # empty override) is how a caller suppresses the semantic-hint-derived annotations, and
          # `MCP::Tool.annotations()` with no kwargs would instead advertise the SDK's own defaults
          # (destructiveHint: true, openWorldHint: true, ...) -- the opposite of what they asked for.
          self.annotations(**resolved_annotations) if resolved_annotations.present?

          define_singleton_method(:call) do |**kwargs|
            # Resolved fresh on every call, not captured once at wrap-time, so a gem-wide config
            # change takes effect immediately, even for tools already wrapped before the change.
            #
            # Reads the wrapped Axn's own per-action override (e.g. `axn_class.configure(:mcp) { |c|
            # c.present_as = :message }`) via Axn::MCP.resolve_override_for rather than
            # axn_class.present_as -- axn_class is a plain Axn that may never have included
            # Axn::MCP.overrides, so it may have no such method at all; resolve_override_for reads
            # the override store directly and falls back to the gem-wide config on its own, with no
            # dependency on axn_class having that accessor.
            Axn::MCP::Invocation.perform(
              axn_class, kwargs,
              text_content: present_as || Axn::MCP.resolve_override_for(axn_class, :present_as),
              reject_opaque_exposed_values: Axn::MCP.resolve_override_for(axn_class, :reject_opaque_exposed_values)
            )
          end
        end
      end

      private

      # `mcp_text_content:` was renamed to `present_as:` (PRO-2923). It's kept as a raising alias --
      # rather than silently dropped -- so a caller still passing it gets a pointed migration error.
      # Detected via a sentinel (not `nil?`), so an explicit `mcp_text_content: nil` is still caught.
      def reject_renamed_mcp_text_content!(value)
        return if value.equal?(RENAMED_MCP_TEXT_CONTENT)

        raise ArgumentError,
              "Axn::MCP.wrap's `mcp_text_content:` was renamed to `present_as:` (PRO-2923). " \
              "Replace `mcp_text_content: #{value.inspect}` with `present_as: #{value.inspect}`."
      end

      # Fail fast on any explicitly-provided invalid value (a typo like :mesage, or `false`)
      # rather than silently falling through to :structured -- matches the validation the
      # `present_as` setting already enforces. `nil` alone means "not provided" (use the resolved
      # per-class/gem-wide value at call time) -- checked via `nil?`, not truthiness, so
      # `present_as: false` can't skip this guard the way a truthy-only check would.
      def validate_present_as!(present_as)
        return if present_as.nil? || VALID_PRESENT_AS.include?(present_as)

        raise ArgumentError, "present_as must be one of #{VALID_PRESENT_AS.map(&:inspect).join(", ")}; got #{present_as.inspect}"
      end

      # `server_context` is reserved: Invocation injects the MCP server context under that key and
      # strips it before calling the Axn (see Invocation.perform). A wrapped Axn declaring it as a
      # normal TOP-LEVEL `expects` (so it surfaces in `input_schema`, unlike an `on: :ambient_context`
      # field, which is excluded) would advertise it as a client argument yet never receive it -- a
      # schema-valid call would then fail the Axn's own validation. Reject at wrap time rather than ship
      # that contradiction; the data an Axn needs from the context goes on `ambient_context`
      # (`expects :user_id, on: :ambient_context`).
      def reject_reserved_input_fields!(axn_class)
        reserved = RESERVED_INPUT_FIELDS & (axn_class.input_schema[:properties] || {}).keys.map(&:to_sym)
        return if reserved.empty?

        raise ArgumentError,
              "Axn::MCP.wrap can't expose #{axn_class}: #{reserved.map(&:inspect).join(", ")} " \
              "#{reserved.one? ? "is a reserved top-level input name" : "are reserved top-level input names"} " \
              "(the wrapper injects the MCP server context there). Declare the data the Axn needs on " \
              "`ambient_context` instead, e.g. `expects :user_id, on: :ambient_context`."
      end

      # Resolve the provider-facing tool name. An explicit `name:` kwarg (most local to the call
      # site) wins; otherwise consume axn core's canonical `tool_name(:mcp)` -- passing the adapter so
      # a per-adapter `tool mcp: { name: "..." }` override wins (PRO-2942), then a shared `tool name:`,
      # then `tool_name_stripped_prefixes` + snake_cased class name. Passing `:mcp` also matches the
      # name `Axn::Tools.for(:mcp)` sorts / collapses to the latest per `tool_name`, so `.tools` and a
      # direct `wrap` agree.
      #
      # Core's `tool_name` never returns blank: a truly anonymous, never-named class (no class name,
      # no `axn_name`) falls back to the generic "tool". That's a footgun for wrap's common inline
      # `tools: [Axn::MCP.wrap(...)]` usage -- every such nameless tool would collide on "tool" and
      # be unregisterable in practice -- so keep wrap's original fail-fast for that case rather than
      # silently shipping a tool named "tool"; require an explicit `name:` instead.
      def resolve_wrap_tool_name(axn_class, name)
        return name if name
        return axn_class.tool_name(:mcp) if axn_class.name.present? || axn_class.axn_name.present?

        raise ArgumentError, "Axn::MCP.wrap requires name: when the wrapped Axn has no derivable class name (#{axn_class}.name is nil)"
      end
    end
  end
end
