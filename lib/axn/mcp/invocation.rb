# frozen_string_literal: true

module Axn
  module MCP
    # Shared "server_context: -> ambient_context: -> call -> MCP::Tool::Response" path used by
    # Axn::MCP.wrap-generated classes (PRO-2844). The injected server_context is passed *as* the
    # Axn's ambient_context (spread, not nested under a `server_context` key), so a wrapped Axn
    # declares the data it needs generically -- `expects :user_id, on: :ambient_context` -- and stays
    # adapter-agnostic (the same class works under axn-ruby_llm, or a direct call resolving from
    # Current). Passing an explicit ambient_context: (even the empty {} when server_context is nil)
    # is what replaces axn core's default Current-attributes-derived ambient_context, stopping
    # server-side Current state from leaking into an MCP call.
    #
    # The raw server_context object -- carrying MCP transport *capabilities* (#report_progress,
    # #cancelled?), which are not ambient data and don't survive ambient_context's declared-key
    # filtering -- is exposed separately via Axn::MCP.server_context for the duration of the call.
    module Invocation
      module_function

      def perform(axn_class, kwargs, text_content:, reject_opaque_exposed_values: false, tool_name: nil)
        # Prefer the Symbol key WHENEVER PRESENT (key?, not `||`/truthiness): an explicit
        # server_context: nil must win over a String-keyed value, or a caller could forge
        # server_context by appending an extra "server_context" argument alongside a real, explicit
        # nil. Only fall back to the String key when the Symbol key is absent entirely -- a
        # forwarding layer that splats a parsed Hash without symbolizing first would otherwise
        # silently lose the real value (it gets stripped below as `rest`, with no reader here to
        # have captured it first).
        server_context = kwargs.key?(:server_context) ? kwargs[:server_context] : kwargs["server_context"]
        # Strip :ambient_context too, not just :server_context, and strip BOTH keys under either
        # a Symbol or a String form: **rest is expanded after the trusted `ambient_context:`
        # literal below, so a caller-supplied `ambient_context:`/`"ambient_context"` kwarg (e.g.
        # smuggled in as an extra tool argument from a transport that splats parsed JSON without
        # symbolizing keys first) would otherwise silently win -- Ruby keeps a String key distinct
        # from the Symbol literal at the splat site, and Axn::Core::Context only symbolizes afterwards
        # (last-write-wins on the collision), so `.except` with Symbol keys alone doesn't catch it.
        rest = kwargs.reject { |k, _| %w[server_context ambient_context].include?(k.to_s) }

        result = Axn::MCP.with_server_context(server_context) do
          axn_class.call(ambient_context: server_context || {}, **rest)
        end

        # Uphold axn's non-bang "never raises" contract at the adapter boundary. The wrapped Axn's own
        # `.call` never raises -- core catches action exceptions into a failed Result and pages
        # on_exception itself -- but the TRANSPORT layer that runs AFTER it (exposed-value
        # serialization, response building) can raise outside core's executor: a value with no honest
        # JSON form (dup keys, non-finite float, non-UTF-8 bytes, an opaque value under
        # reject_opaque_exposed_values), a structure past JSON's max_nesting, or a gem bug. Scope the
        # guard to just that step (NOT axn_class.call, which already handles its own exceptions, to
        # avoid double-reporting), report through axn's global on_exception hook for observability,
        # then -- honoring core's `best_effort_raises_in_dev` so a real bug surfaces loudly rather
        # than being masked -- re-raise in dev, otherwise return an error response so `.call` ALWAYS
        # yields an MCP::Tool::Response on every transport (not an escaped exception).
        begin
          Serializer.result_to_mcp_response(result, text_content:, reject_opaque_exposed_values:)
        rescue StandardError => e
          # Report best-effort: a broken `on_exception` reporter must not itself break this guard's
          # own never-raises contract on the very path it exists to normalize (mirrors how core wraps
          # its own on_exception). best_effort swallows a reporter failure outside dev; in dev it, like
          # the `raise` below, surfaces loudly.
          Axn::Extensions.best_effort("Axn::MCP transport-failure report", action: axn_class) do
            Axn.config.on_exception(e, action: axn_class, context: { source: "Axn::MCP" })
          end

          # The user-facing response stays generic (ADAPTER_FAILURE_MESSAGE) -- this line is an
          # operator's only pointer to WHY. Mirrors axn-openapi's dispatcher hint: the config pointer
          # lives HERE rather than in core's exception message, since core raises the same error for
          # adapters with no such setting. Named as BOTH config levels, never just the gem-wide setter
          # -- the value is resolved per-tool, so a `configure(:mcp)` override beats `config`, and core
          # exposes no way to ask which level supplied a resolved value. Non-committal ("if this is")
          # because reject_opaque_exposed_values being on doesn't mean THIS failure is an opaque
          # rejection -- it could equally be a colliding key, a non-finite Float, or a gem bug.
          #
          # Named by the MCP-facing tool_name (from wrap's `resolved_name`), not the wrapped Axn's own
          # class name: `Axn::MCP.wrap` lets the same Axn mount under a different name per call site
          # (an explicit `name:`, or a per-adapter `tool mcp: { name: }` override), and an operator
          # correlating this line with a failed MCP request has the REQUEST's tool name, not the class's.
          # Falls back to `resolved_axn_name` (axn core) for a caller of `perform` outside `wrap` (the
          # specs below) -- never raw `#{axn_class}`: Class#to_s does NOT dispatch through an overridden
          # `.name` (it renders the object-id form regardless), so a class with no assigned constant --
          # e.g. one built via Axn::Factory.build -- would otherwise show as `#<Class:0x...>` instead of
          # naming the action. Built INSIDE the best_effort block, not before it: both tool_name and
          # axn_class are caller-supplied, so a hostile/buggy override must not raise outside the guard
          # meant to contain exactly that. A separate best_effort from the on_exception report above,
          # deliberately: a broken configured logger must not suppress the on_exception report (which
          # already ran), and a broken on_exception reporter must not suppress this diagnostic line either
          # -- each is the guard's only surviving signal when the OTHER one is what's broken.
          Axn::Extensions.best_effort("Axn::MCP transport-failure diagnostic log", action: axn_class) do
            hint = if reject_opaque_exposed_values
                     display_name = tool_name || axn_class.resolved_axn_name
                     " (if this is an opaque-value rejection: reject_opaque_exposed_values resolved true for " \
                       "#{display_name} — unset it on the action via `configure(:mcp)`, or " \
                       "gem-wide via `Axn::MCP.config.reject_opaque_exposed_values = false`, whichever is set)"
                   else
                     ""
                   end
            Axn.config.logger.error { "[axn-mcp] failed to serialize successful result: #{e.class}: #{e.message}#{hint}" }
          end

          raise if Axn::Extensions.raises_in_dev?

          Serializer.error_response(Serializer::ADAPTER_FAILURE_MESSAGE)
        end
      end
    end
  end
end
