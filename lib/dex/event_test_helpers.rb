# frozen_string_literal: true

module Dex
  class Event
    module EventTestWrapper
      CAPTURING_KEY = :_dex_event_capturing
      PUBLISHED_KEY = :_dex_event_published

      @_installed = false

      class << self
        include ExecutionState

        def install!
          return if @_installed

          Dex::Event::Bus.singleton_class.prepend(BusInterceptor)
          @_installed = true
        end

        def installed?
          @_installed
        end

        def capturing?
          (_execution_state[CAPTURING_KEY] || 0) > 0
        end

        def begin_capture!
          _execution_state[CAPTURING_KEY] = (_execution_state[CAPTURING_KEY] || 0) + 1
        end

        def end_capture!
          depth = (_execution_state[CAPTURING_KEY] || 0) - 1
          _execution_state[CAPTURING_KEY] = [depth, 0].max
        end

        def published_events
          _execution_state[PUBLISHED_KEY] ||= []
        end

        def clear_published!
          _execution_state[PUBLISHED_KEY] = []
        end
      end

      module BusInterceptor
        def publish(event, sync:)
          if Dex::Event::EventTestWrapper.capturing?
            return if Dex::Event::Suppression.suppressed?(event.class)

            Dex::Event::EventTestWrapper.published_events << event
          else
            super(event, sync: true)
          end
        end
      end
    end

    module TestHelpers
      def self.included(base)
        EventTestWrapper.install!
      end

      def setup
        super
        EventTestWrapper.clear_published!
        Dex::Event::Trace.clear!
        Dex::Event::Suppression.clear!
      end

      def capture_events
        EventTestWrapper.begin_capture!
        yield
      ensure
        EventTestWrapper.end_capture!
      end

      private

      def _dex_published_events
        EventTestWrapper.published_events
      end
    end
  end
end

require_relative "event_test_helpers/assertions"
