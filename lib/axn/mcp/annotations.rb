# frozen_string_literal: true

module Axn
  module MCP
    # Maps axn core's `semantic_hints` vocabulary (plus the MCP-only extensions this adapter
    # registers below) to MCP tool annotation kwargs. Registering :open_world/:closed_world via
    # Axn.extension_config.register_semantic_hint is the poster-child use of PRO-2842's registry:
    # no core change was needed to add MCP-spec-only vocabulary.
    module Annotations
      # read_only also asserts destructive_hint: false: MCP::Tool::Annotations defaults
      # destructive_hint to true, so without this a read_only tool would be advertised as BOTH
      # read-only and destructive -- the same contradiction the legacy read_only! bang method
      # already avoided by setting both explicitly. A later :destructive in the same hints list
      # still wins (annotations_for merges in order), for a tool that means both.
      HINT_TO_ANNOTATION = {
        read_only: { read_only_hint: true, destructive_hint: false },
        idempotent: { idempotent_hint: true },
        destructive: { destructive_hint: true },
        open_world: { open_world_hint: true },
        closed_world: { open_world_hint: false },
      }.freeze

      module_function

      def annotations_for(hints)
        hints.each_with_object({}) { |hint, acc| acc.merge!(HINT_TO_ANNOTATION.fetch(hint, {})) }
      end
    end
  end
end
