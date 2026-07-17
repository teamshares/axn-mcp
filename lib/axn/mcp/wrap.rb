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
        Axn.tools_for(:mcp).map { |axn_class| wrap(axn_class) }
      end

      def wrap(axn_class, description: nil, name: nil, title: nil, icons: nil, meta: nil, annotations: nil,
               present_as: nil, mcp_text_content: RENAMED_MCP_TEXT_CONTENT)
        reject_renamed_mcp_text_content!(mcp_text_content)
        validate_present_as!(present_as)
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

        Class.new(::MCP::Tool) do
          tool_name(resolved_name)
          description(resolved_description)
          title(resolved_title) if resolved_title
          icons(resolved_icons) if resolved_icons
          meta(resolved_meta) if resolved_meta

          # axn_class.input_schema/.output_schema are axn core's own public reflection surface
          # (Axn::Core::SchemaReflection) -- wiring to those directly, rather than reaching past
          # them for the lower-level Axn::Reflection::Schema.build_input/build_output the wrapped
          # Axn's own methods already call, keeps this on the documented entry point.
          input_schema(axn_class.input_schema)
          output_schema(axn_class.output_schema) unless axn_class.external_field_configs.empty?

          hint_annotations = Axn::MCP::Annotations.annotations_for(axn_class._semantic_hints)
          resolved_annotations = configured_annotations || (hint_annotations if hint_annotations.any?)
          self.annotations(**resolved_annotations) if resolved_annotations

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
            Axn::MCP::Invocation.perform(axn_class, kwargs,
                                         text_content: present_as || Axn::MCP.resolve_override_for(axn_class, :present_as))
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

      # Resolve the provider-facing tool name. An explicit `name:` kwarg (most local to the call
      # site) wins; otherwise consume axn core's canonical `tool_name` (PRO-2923) -- which honors a
      # `tool name: "..."` override on the wrapped Axn and its `tool_name_stripped_prefixes`, and
      # snake_cases the class name -- replacing the old `::MCP::StringUtils.handle_from_class_name`.
      #
      # Core's `tool_name` never returns blank: a truly anonymous, never-named class (no class name,
      # no `axn_name`) falls back to the generic "tool". That's a footgun for wrap's common inline
      # `tools: [Axn::MCP.wrap(...)]` usage -- every such nameless tool would collide on "tool" and
      # be unregisterable in practice -- so keep wrap's original fail-fast for that case rather than
      # silently shipping a tool named "tool"; require an explicit `name:` instead.
      def resolve_wrap_tool_name(axn_class, name)
        return name if name
        return axn_class.tool_name if axn_class.name.present? || axn_class.axn_name.present?

        raise ArgumentError, "Axn::MCP.wrap requires name: when the wrapped Axn has no derivable class name (#{axn_class}.name is nil)"
      end
    end
  end
end
