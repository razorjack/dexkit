# frozen_string_literal: true

module Dex
  class Event
    module Trace
      class << self
        def with_event(event, &block)
          Dex::Trace.with_event_context(event, &block)
        end

        def current_event_id
          Dex::Trace.current_event_id
        end

        def current_trace_id
          Dex::Trace.trace_id
        end

        def dump
          Dex::Trace.dump
        end

        def restore(data, &block)
          return yield unless data

          if data.is_a?(Hash) && (data.key?(:frames) || data.key?("frames"))
            Dex::Trace.restore(data, &block)
          else
            Dex::Trace.restore_event_context(
              event_id: data[:id] || data["id"],
              trace_id: data[:trace_id] || data["trace_id"],
              &block
            )
          end
        end

        def clear!
          Dex::Trace.clear!
        end
      end
    end
  end
end
