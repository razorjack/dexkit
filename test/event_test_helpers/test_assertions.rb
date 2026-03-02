# frozen_string_literal: true

require "test_helper"
require "dex/event_test_helpers"

class TestEventAssertions < Minitest::Test
  include Dex::Event::TestHelpers

  def test_assert_event_published
    event_class = build_event do
      prop :order_id, Integer
    end

    capture_events do
      event_class.new(order_id: 1).publish
      assert_event_published(event_class)
    end
  end

  def test_assert_event_published_with_props
    event_class = build_event do
      prop :order_id, Integer
      prop :total, Float
    end

    capture_events do
      event_class.new(order_id: 1, total: 99.99).publish
      assert_event_published(event_class, order_id: 1)
      assert_event_published(event_class, total: 99.99)
      assert_event_published(event_class, order_id: 1, total: 99.99)
    end
  end

  def test_assert_event_published_fails_when_not_published
    event_class = build_event do
      prop :n, Integer
    end

    capture_events do
      err = assert_raises(Minitest::Assertion) do
        assert_event_published(event_class)
      end
      assert_match(/no events were published/, err.message)
    end
  end

  def test_assert_event_published_fails_with_wrong_props
    event_class = build_event do
      prop :n, Integer
    end

    capture_events do
      event_class.new(n: 1).publish
      err = assert_raises(Minitest::Assertion) do
        assert_event_published(event_class, n: 999)
      end
      assert_match(/only found/, err.message)
    end
  end

  def test_refute_event_published_no_args
    capture_events do
      refute_event_published
    end
  end

  def test_refute_event_published_with_class
    event_a = build_event do
      prop :a, Integer
    end

    event_b = build_event do
      prop :b, Integer
    end

    capture_events do
      event_a.new(a: 1).publish
      refute_event_published(event_b)
    end
  end

  def test_refute_event_published_fails_when_published
    event_class = build_event do
      prop :n, Integer
    end

    capture_events do
      event_class.new(n: 1).publish
      assert_raises(Minitest::Assertion) do
        refute_event_published
      end
    end
  end

  def test_assert_event_count
    event_class = build_event do
      prop :n, Integer
    end

    capture_events do
      event_class.new(n: 1).publish
      event_class.new(n: 2).publish
      assert_event_count(event_class, 2)
    end
  end

  def test_assert_event_trace
    parent_class = build_event do
      prop :name, String
    end

    child_class = build_event do
      prop :value, Integer
    end

    parent = parent_class.new(name: "root")
    child = nil

    parent.trace do
      child = child_class.new(value: 42)
    end

    assert_event_trace(parent, child)
  end

  def test_assert_same_trace
    event_class = build_event do
      prop :n, Integer
    end

    root = event_class.new(n: 0)
    events = [root]

    root.trace do
      e1 = event_class.new(n: 1)
      events << e1
      e1.trace do
        events << event_class.new(n: 2)
      end
    end

    assert_same_trace(*events)
  end

  def test_assert_same_trace_fails_different_traces
    event_class = build_event do
      prop :n, Integer
    end

    a = event_class.new(n: 1)
    b = event_class.new(n: 2)

    assert_raises(Minitest::Assertion) do
      assert_same_trace(a, b)
    end
  end

  def test_capture_respects_suppression
    event_class = build_event do
      prop :n, Integer
    end

    capture_events do
      Dex::Event.suppress(event_class) do
        event_class.new(n: 1).publish
      end
      refute_event_published
    end
  end

  def test_outside_capture_forces_sync
    event_class = build_event do
      prop :n, Integer
    end

    received = []
    build_handler do
      on event_class
      define_method(:perform) { received << event }
    end

    # Outside capture_events, publish dispatches sync
    event_class.new(n: 1).publish
    assert_equal 1, received.size
  end

  def test_nested_capture_events
    event_class = build_event do
      prop :n, Integer
    end

    capture_events do
      event_class.new(n: 1).publish

      capture_events do
        event_class.new(n: 2).publish
      end

      # Outer capture should still be active after inner block exits
      event_class.new(n: 3).publish
      assert_event_count(event_class, 3)
    end
  end

  def test_multiple_event_types
    event_a = build_event do
      prop :a, Integer
    end

    event_b = build_event do
      prop :b, Integer
    end

    capture_events do
      event_a.new(a: 1).publish
      event_b.new(b: 2).publish

      assert_event_published(event_a, a: 1)
      assert_event_published(event_b, b: 2)
      assert_event_count(event_a, 1)
      assert_event_count(event_b, 1)
    end
  end
end
