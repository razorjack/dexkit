# frozen_string_literal: true

module Dex
  class Event
    class Metadata
      attr_reader :id, :timestamp, :trace_id, :caused_by_id, :event_ancestry

      def initialize(id:, timestamp:, trace_id:, caused_by_id:, event_ancestry:)
        @id = id
        @timestamp = timestamp
        @trace_id = trace_id
        @caused_by_id = caused_by_id
        @event_ancestry = event_ancestry
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

        new(
          id: id,
          timestamp: Time.now.utc,
          trace_id: trace_id,
          caused_by_id: caused,
          event_ancestry: ancestry
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
        h
      end
    end
  end
end
