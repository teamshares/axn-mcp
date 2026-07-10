# frozen_string_literal: true

module Axn
  module MCP
    # Shared "server_context: -> ambient_context: -> call -> MCP::Tool::Response" path used by both
    # Axn::MCP::Tool#call (the with-server_context branch, back-compat dual-mode) and
    # Axn::MCP.wrap-generated classes (PRO-2844). An explicit ambient_context: kwarg replaces axn
    # core's default Current-attributes-derived ambient_context (see Axn::Core::AmbientContext) --
    # passing it here even when server_context is nil is what stops server-side Current leaking in.
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

        result = axn_class.call(ambient_context: { server_context: }, **rest)
        Serializer.result_to_mcp_response(result, axn_class.external_field_configs, text_content:)
      end
    end
  end
end
