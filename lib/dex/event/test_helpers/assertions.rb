# frozen_string_literal: true

module Dex
  class Event
    module TestHelpers
      def assert_event_published(event_class, msg: nil, **expected_props)
        matching = _dex_find_published_events(event_class, expected_props)
        assert matching.any?,
          msg || _dex_event_published_failure_message(event_class, expected_props)
      end

      def refute_event_published(event_class = nil, msg: nil, **expected_props)
        if event_class.nil?
          assert _dex_published_events.empty?,
            msg || "Expected no events published, but #{_dex_published_events.size} were:\n#{_dex_event_list}"
        else
          matching = _dex_find_published_events(event_class, expected_props)
          assert matching.empty?,
            msg || "Expected no #{event_class.name || event_class} events published, but found #{matching.size}"
        end
      end

      def assert_event_count(event_class, count, msg: nil)
        matching = _dex_find_published_events(event_class, {})
        assert_equal count, matching.size,
          msg || "Expected #{count} #{event_class.name || event_class} events, got #{matching.size}"
      end

      def assert_event_trace(parent, child, msg: nil)
        assert_equal parent.id, child.caused_by_id,
          msg || "Expected child event to be caused by parent (caused_by_id mismatch)"
      end

      def assert_same_trace(*events, msg: nil)
        trace_ids = events.map(&:trace_id).uniq
        assert_equal 1, trace_ids.size,
          msg || "Expected all events to share the same trace_id, got: #{trace_ids.inspect}"
      end

      private

      def _dex_find_published_events(event_class, expected_props)
        _dex_published_events.select do |event|
          next false unless event.is_a?(event_class)

          expected_props.all? do |key, value|
            event.respond_to?(key) && event.public_send(key) == value
          end
        end
      end

      def _dex_event_published_failure_message(event_class, expected_props)
        name = event_class.name || event_class.to_s
        if _dex_published_events.empty?
          "Expected #{name} to be published, but no events were published"
        else
          msg = "Expected #{name} to be published"
          msg += " with #{expected_props.inspect}" unless expected_props.empty?
          msg + ", but only found:\n#{_dex_event_list}"
        end
      end

      def _dex_event_list
        _dex_published_events.map.with_index do |event, i|
          "  #{i + 1}. #{event.class.name || event.class}"
        end.join("\n")
      end
    end
  end
end
