# frozen_string_literal: true

require "test_helper"

class TestEventTrace < Minitest::Test
  def test_trace_sets_caused_by
    parent_class = build_event do
      prop :name, String
    end

    child_class = build_event do
      prop :value, Integer
    end

    parent = parent_class.new(name: "parent")
    child = nil

    parent.trace do
      child = child_class.new(value: 42)
    end

    assert_equal parent.id, child.caused_by_id
    assert_equal parent.trace_id, child.trace_id
  end

  def test_nested_trace
    event_a_class = build_event do
      prop :a, Integer
    end

    event_b_class = build_event do
      prop :b, Integer
    end

    event_c_class = build_event do
      prop :c, Integer
    end

    a = event_a_class.new(a: 1)
    b = nil
    c = nil

    a.trace do
      b = event_b_class.new(b: 2)
      b.trace do
        c = event_c_class.new(c: 3)
      end
    end

    assert_equal a.id, b.caused_by_id
    assert_equal a.trace_id, b.trace_id
    assert_equal b.id, c.caused_by_id
    assert_equal a.trace_id, c.trace_id
  end

  def test_trace_id_inherited_through_chain
    root_class = build_event do
      prop :n, Integer
    end

    root = root_class.new(n: 0)
    events = [root]

    root.trace do
      e1 = root_class.new(n: 1)
      events << e1
      e1.trace do
        e2 = root_class.new(n: 2)
        events << e2
      end
    end

    assert events.all? { |e| e.trace_id == root.trace_id }
  end

  def test_no_trace_context_by_default
    assert_nil Dex::Event::Trace.current_event_id
    assert_nil Dex::Event::Trace.current_trace_id
  end

  def test_dump_and_restore
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "original")
    dumped = nil

    event.trace do
      dumped = Dex::Event::Trace.dump
    end

    assert_equal event.id, dumped[:id]
    assert_equal event.trace_id, dumped[:trace_id]

    inner_child = nil
    Dex::Event::Trace.restore(dumped) do
      inner_child = event_class.new(name: "restored")
    end

    assert_equal event.id, inner_child.caused_by_id
    assert_equal event.trace_id, inner_child.trace_id
  end

  def test_restore_nil_is_noop
    event_class = build_event do
      prop :name, String
    end

    Dex::Event::Trace.restore(nil) do
      event = event_class.new(name: "test")
      assert_nil event.caused_by_id
    end
  end

  def test_clear
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    event.trace do
      Dex::Event::Trace.clear!
      assert_nil Dex::Event::Trace.current_event_id
    end
  end

  def test_handler_runs_under_dispatched_event_frame
    parent_class = build_event do
      prop :name, String
    end

    child_class = build_event do
      prop :value, Integer
    end

    children = []
    build_handler do
      on parent_class
      define_method(:perform) do
        children << child_class.new(value: 1)
      end
    end

    parent = parent_class.new(name: "root")
    parent.publish(sync: true)

    assert_equal 1, children.size
    assert_equal parent.id, children.first.caused_by_id
    assert_equal parent.trace_id, children.first.trace_id
  end

  def test_handler_chain_preserves_causality
    event_class = build_event do
      prop :n, Integer
    end

    events_seen = []

    # Handler for n=1 publishes n=2
    build_handler do
      on event_class
      define_method(:perform) do
        events_seen << event
        event_class.new(n: event.n + 1).publish(sync: true) if event.n < 3
      end
    end

    root = event_class.new(n: 1)
    root.publish(sync: true)

    assert_equal 3, events_seen.size
    # Second event caused by first
    assert_equal events_seen[0].id, events_seen[1].caused_by_id
    # Third event caused by second
    assert_equal events_seen[1].id, events_seen[2].caused_by_id
    # All share root's trace_id
    assert events_seen.all? { |e| e.trace_id == root.trace_id }
  end
end
