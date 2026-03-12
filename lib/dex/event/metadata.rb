# frozen_string_literal: true

module Dex
  class Event
    class Metadata
      attr_reader :id, :timestamp, :trace_id, :caused_by_id, :event_ancestry, :context

      def initialize(id:, timestamp:, trace_id:, caused_by_id:, event_ancestry:, context:)
        @id = id
        @timestamp = timestamp
        @trace_id = trace_id
        @caused_by_id = caused_by_id
        @event_ancestry = event_ancestry
        @context = context
        freeze
      end

      def self.build
        id = Dex::Id.generate("ev_")
        trace_id = Dex::Trace.trace_id || Dex::Id.generate("tr_")
        current_event = Dex::Trace.current_event_context
        caused = current_event&.dig(:id)
        ancestry = if current_event
          Array(current_event[:event_ancestry]) + [caused].compact
        else
          []
        end

        ctx = if Dex.configuration.event_context
          begin
            Dex.configuration.event_context.call
          rescue => e
            Event._warn("event_context failed: #{e.message}")
            nil
          end
        end

        new(
          id: id,
          timestamp: Time.now.utc,
          trace_id: trace_id,
          caused_by_id: caused,
          event_ancestry: ancestry,
          context: ctx
        )
      end

      def as_json
        h = {
          "id" => @id,
          "timestamp" => @timestamp.iso8601(6),
          "trace_id" => @trace_id,
          "event_ancestry" => @event_ancestry
        }
        h["caused_by_id"] = @caused_by_id if @caused_by_id
        h["context"] = @context if @context
        h
      end
    end
  end
end
