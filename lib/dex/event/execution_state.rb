# frozen_string_literal: true

module Dex
  class Event
    module ExecutionState
      private

      def _execution_state
        if defined?(ActiveSupport::IsolatedExecutionState)
          ActiveSupport::IsolatedExecutionState
        else
          Thread.current
        end
      end
    end
  end
end
