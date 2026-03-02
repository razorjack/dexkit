# frozen_string_literal: true

module Dex
  class Event
    module Trace
      STACK_KEY = :_dex_event_trace_stack

      class << self
        include ExecutionState

        def with_event(event, &block)
          stack = _stack
          stack.push(event.trace_frame)
          yield
        ensure
          stack.pop
        end

        def current_event_id
          _stack.last&.dig(:id)
        end

        def current_trace_id
          _stack.last&.dig(:trace_id)
        end

        def dump
          frame = _stack.last
          return nil unless frame

          { id: frame[:id], trace_id: frame[:trace_id] }
        end

        def restore(data, &block)
          return yield unless data

          stack = _stack
          stack.push(data)
          yield
        ensure
          stack.pop if data
        end

        def clear!
          _execution_state[STACK_KEY] = []
        end

        private

        def _stack
          _execution_state[STACK_KEY] ||= []
        end
      end
    end
  end
end
