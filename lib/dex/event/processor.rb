# frozen_string_literal: true

module Dex
  class Event
    # Lazy-loaded ActiveJob processor (same pattern as Operation::DirectJob)
    def self.const_missing(name)
      return super unless name == :Processor && defined?(ActiveJob::Base)

      const_set(:Processor, Class.new(ActiveJob::Base) do
        def perform(handler_class:, event_class:, payload:, metadata:, trace: nil, context: nil, attempt_number: 1)
          _processor_restore_context(context)

          handler = Object.const_get(handler_class)
          retry_config = handler._event_handler_retry_config

          Dex::Event::Trace.restore(trace) do
            handler._event_handle_from_payload(event_class, payload, metadata)
          end
        rescue => _e
          if retry_config && attempt_number <= retry_config[:count]
            delay = _processor_compute_delay(retry_config, attempt_number)
            self.class.set(wait: delay).perform_later(
              handler_class: handler_class,
              event_class: event_class,
              payload: payload,
              metadata: metadata,
              trace: trace,
              context: context,
              attempt_number: attempt_number + 1
            )
          else
            raise
          end
        end

        private

        def _processor_restore_context(context)
          return unless context

          restorer = Dex.configuration.restore_event_context
          return unless restorer

          restorer.call(context)
        rescue => e
          Dex::Event._warn("restore_event_context failed: #{e.message}")
        end

        def _processor_compute_delay(config, attempt)
          wait = config[:wait]
          case wait
          when Numeric then wait
          when Proc then wait.call(attempt)
          else
            2**(attempt - 1) # exponential backoff
          end
        end
      end)
    end
  end
end
