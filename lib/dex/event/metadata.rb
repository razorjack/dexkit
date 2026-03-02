# frozen_string_literal: true

require "securerandom"

module Dex
  class Event
    class Metadata
      attr_reader :id, :timestamp, :trace_id, :caused_by_id, :context

      def initialize(id:, timestamp:, trace_id:, caused_by_id:, context:)
        @id = id
        @timestamp = timestamp
        @trace_id = trace_id
        @caused_by_id = caused_by_id
        @context = context
        freeze
      end

      def self.build(caused_by_id: nil)
        id = SecureRandom.uuid
        trace_id = Trace.current_trace_id || id
        caused = caused_by_id || Trace.current_event_id

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
          context: ctx
        )
      end

      def as_json
        h = {
          "id" => @id,
          "timestamp" => @timestamp.iso8601(6),
          "trace_id" => @trace_id
        }
        h["caused_by_id"] = @caused_by_id if @caused_by_id
        h["context"] = @context if @context
        h
      end
    end
  end
end
