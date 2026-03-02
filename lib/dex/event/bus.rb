# frozen_string_literal: true

module Dex
  class Event
    class Bus
      @_subscribers = {}
      @_mutex = Mutex.new

      class << self
        def subscribe(event_class, handler_class)
          unless event_class.is_a?(Class) && event_class < Dex::Event
            raise ArgumentError, "#{event_class.inspect} is not a Dex::Event subclass"
          end
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
            @_subscribers[event_class]&.delete(handler_class)
            @_subscribers.delete(event_class) if @_subscribers[event_class] && @_subscribers[event_class].empty?
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

          _event_bus_persist(event)
          handlers = subscribers_for(event.class)
          return if handlers.empty?

          event_frame = { id: event.id, trace_id: event.trace_id }

          handlers.each do |handler_class|
            if sync
              Trace.restore(event_frame) do
                handler_class._event_handle(event)
              end
            else
              _event_bus_enqueue(handler_class, event, event_frame)
            end
          end
        end

        def clear!
          @_mutex.synchronize { @_subscribers.clear }
        end

        private

        def _event_bus_persist(event)
          store = Dex.configuration.event_store
          return unless store

          store.create!(
            event_type: event.class.name,
            payload: event._props_as_json,
            metadata: event.metadata.as_json
          )
        rescue => e
          Event._warn("Failed to persist event: #{e.message}")
        end

        def _event_bus_enqueue(handler_class, event, trace_data)
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
      end
    end
  end
end
