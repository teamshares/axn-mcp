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

      def perform(axn_class, kwargs, text_content:)
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
        # from the Symbol literal at the splat site, and Axn::Context only symbolizes afterwards
        # (last-write-wins on the collision), so `.except` with Symbol keys alone doesn't catch it.
        rest = kwargs.reject { |k, _| %w[server_context ambient_context].include?(k.to_s) }

        result = Axn::MCP.with_server_context(server_context) do
          axn_class.call(ambient_context: server_context || {}, **rest)
        end
        Serializer.result_to_mcp_response(result, axn_class.external_field_configs, text_content:)
      end
    end
  end
end
