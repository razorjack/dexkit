# frozen_string_literal: true

module Dex
  module TraceWrapper
    extend Dex::Concern

    def _trace_wrap
      @_dex_execution_id ||= Dex::Id.generate("op_")

      Dex::Trace.with_frame(
        type: :operation,
        id: @_dex_execution_id,
        class: self.class.name
      ) do
        @_dex_trace_id = Dex::Trace.trace_id
        yield
      end
    end
  end
end
