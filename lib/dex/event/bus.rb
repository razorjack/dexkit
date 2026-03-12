# frozen_string_literal: true

module Dex
  class Event
    class Bus
      @_subscribers = {}
      @_mutex = Mutex.new

      class << self
        def subscribe(event_class, handler_class)
          Event.validate_event_class!(event_class)
          unless handler_class.is_a?(Class) && handler_class < Dex::Event::Handler
            raise ArgumentError, "#{handler_class.inspect} is not a Dex::Event::Handler subclass"
          end

          @_mutex.synchronize do
            @_subscribers[event_class] ||= []
            @_subscribers[event_class] |= [handler_class]
          end
        end

        def unsubscribe(event_class, handler_class)
          @_mutex.synchronize do
            list = @_subscribers[event_class]
            return unless list

            list.delete(handler_class)
            @_subscribers.delete(event_class) if list.empty?
          end
        end

        def subscribers_for(event_class)
          @_mutex.synchronize do
            @_subscribers.each_with_object([]) do |(subscribed_class, handlers), result|
              result.concat(handlers) if event_class <= subscribed_class
            end.uniq
          end
        end

        def subscribers
          @_mutex.synchronize { @_subscribers.transform_values(&:dup) }
        end

        def publish(event, sync:)
          return if Suppression.suppressed?(event.class)

          trace_data = trace_data_for(event)
          persist(event, trace_data)
          handlers = subscribers_for(event.class)
          return if handlers.empty?

          handlers.each do |handler_class|
            if sync
              Dex::Trace.restore(trace_data) do
                handler_class._event_handle(event)
              end
            else
              enqueue(handler_class, event, trace_data)
            end
          end
        end

        def clear!
          @_mutex.synchronize { @_subscribers.clear }
        end

        private

        def persist(event, trace_data)
          store = Dex.configuration.event_store
          return unless store

          actor = actor_from_trace(trace_data[:frames])
          attrs = safe_store_attributes(store, {
            id: event.id,
            trace_id: event.trace_id,
            actor_type: actor&.dig(:actor_type),
            actor_id: actor&.dig(:id),
            trace: trace_data[:frames],
            event_type: event.class.name,
            payload: event._props_as_json,
            metadata: event.metadata.as_json
          })

          store.create!(**attrs)
        rescue => e
          Event._warn("Failed to persist event: #{e.message}")
        end

        def enqueue(handler_class, event, trace_data)
          ensure_active_job_loaded!
          ctx = event.context

          Dex::Event::Processor.perform_later(
            handler_class: handler_class.name,
            event_class: event.class.name,
            payload: event._props_as_json,
            metadata: event.metadata.as_json,
            trace: trace_data,
            context: ctx
          )
        end

        def trace_data_for(event)
          ambient = Dex::Trace.dump
          frames = if ambient && trace_matches_event?(ambient, event)
            trace_frames(ambient)
          elsif ambient
            actor_frames(trace_frames(ambient))
          else
            []
          end

          {
            trace_id: event.trace_id,
            frames: frames,
            event_context: event_context_for(event)
          }
        end

        def actor_from_trace(frames)
          Array(frames).find do |frame|
            frame_type = frame[:type] || frame["type"]
            frame_type && frame_type.to_sym == :actor
          end
        end

        def actor_frames(frames)
          Array(frames).select do |frame|
            frame_type = frame[:type] || frame["type"]
            frame_type && frame_type.to_sym == :actor
          end
        end

        def trace_frames(trace_data)
          Array(trace_data[:frames] || trace_data["frames"])
        end

        def trace_matches_event?(trace_data, event)
          trace_id = trace_data[:trace_id] || trace_data["trace_id"]
          trace_id.to_s == event.trace_id.to_s
        end

        def event_context_for(event)
          {
            id: event.id,
            trace_id: event.trace_id,
            event_class: event.class.name,
            event_ancestry: event.event_ancestry
          }
        end

        def safe_store_attributes(store, attributes)
          if store.respond_to?(:column_names)
            allowed = store.column_names.to_set
            attributes.select { |key, _| allowed.include?(key.to_s) }
          elsif store.respond_to?(:fields)
            attributes.select do |key, _|
              field_name = key.to_s
              store.fields.key?(field_name) || (field_name == "id" && store.fields.key?("_id"))
            end
          else
            attributes
          end
        end

        def ensure_active_job_loaded!
          return if defined?(ActiveJob::Base)

          raise LoadError, "ActiveJob is required for async event handlers. Add 'activejob' to your Gemfile."
        end
      end
    end
  end
end
