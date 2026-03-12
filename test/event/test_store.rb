# frozen_string_literal: true

require "test_helper"

class TestEventStore < Minitest::Test
  def test_no_persistence_without_config
    event_class = build_event do
      prop :n, Integer
    end

    build_handler do
      on event_class
      def perform
      end
    end

    # Should not raise even without event_store
    event_class.new(n: 1).publish(sync: true)
  end

  def test_persists_when_configured
    event_class = build_event do
      prop :n, Integer
    end

    build_handler do
      on event_class
      def perform
      end
    end

    store = Minitest::Mock.new
    store.expect :create!, nil do |attrs|
      attrs[:id] &&
        attrs[:trace_id] &&
        attrs[:actor_type] == "user" &&
        attrs[:actor_id] == "7" &&
        attrs[:trace].is_a?(Array) &&
        attrs[:event_type] &&
        attrs[:payload] &&
        attrs[:metadata]
    end

    Dex.configure { |c| c.event_store = store }

    Dex::Trace.start(actor: { type: :user, id: 7 }) do
      event_class.new(n: 42).publish(sync: true)
    end
    assert_mock store
  ensure
    Dex.configure { |c| c.event_store = nil }
  end

  def test_persistence_failure_does_not_halt_publish
    event_class = build_event do
      prop :n, Integer
    end

    received = []
    build_handler do
      on event_class
      define_method(:perform) { received << event }
    end

    broken_store = Object.new
    def broken_store.create!(**) = raise("db down")

    Dex.configure { |c| c.event_store = broken_store }

    event_class.new(n: 1).publish(sync: true)
    assert_equal 1, received.size
  ensure
    Dex.configure { |c| c.event_store = nil }
  end
end
