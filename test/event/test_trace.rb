# frozen_string_literal: true

require "test_helper"

class TestEventTrace < Minitest::Test
  def test_publish_with_caused_by_sets_caused_by
    parent_class = build_event do
      prop :name, String
    end

    child_class = build_event do
      prop :value, Integer
    end

    parent = parent_class.new(name: "parent")
    child = nil

    build_handler do
      on child_class
      define_method(:perform) { child = event }
    end

    child_class.publish(value: 42, caused_by: parent, sync: true)

    assert_equal parent.id, child.caused_by_id
    assert_equal parent.trace_id, child.trace_id
    assert_equal [parent.id], child.event_ancestry
  end

  def test_nested_causality_tracks_event_ancestry
    event_class = build_event do
      prop :n, Integer
    end

    events_seen = []

    build_handler do
      on event_class
      define_method(:perform) do
        events_seen << event
        event_class.publish(n: event.n + 1, sync: true) if event.n < 3
      end
    end

    event_class.new(n: 1).publish(sync: true)

    assert_equal 3, events_seen.size
    assert_equal [], events_seen[0].event_ancestry
    assert_equal [events_seen[0].id], events_seen[1].event_ancestry
    assert_equal [events_seen[0].id, events_seen[1].id], events_seen[2].event_ancestry
  end

  def test_nested_publish_after_caused_by_uses_current_handler_event
    parent_class = build_event do
      prop :name, String
    end

    event_class = build_event do
      prop :n, Integer
    end

    events_seen = []

    build_handler do
      on event_class
      define_method(:perform) do
        events_seen << event
        event_class.publish(n: event.n + 1, sync: true) if event.n == 1
      end
    end

    parent = parent_class.new(name: "parent")
    event_class.publish(n: 1, caused_by: parent, sync: true)

    assert_equal 2, events_seen.size
    assert_equal parent.id, events_seen[0].caused_by_id
    assert_equal [parent.id], events_seen[0].event_ancestry
    assert_equal events_seen[0].id, events_seen[1].caused_by_id
    assert_equal [parent.id, events_seen[0].id], events_seen[1].event_ancestry
  end

  def test_prebuilt_event_publish_keeps_original_trace_id
    event_class = build_event do
      prop :n, Integer
    end

    seen_trace_id = nil
    child = nil

    build_handler do
      on event_class
      define_method(:perform) do
        seen_trace_id = Dex::Trace.trace_id
        child = event_class.new(n: event.n + 1)
      end
    end

    original = event_class.new(n: 1)
    original_trace_id = original.trace_id

    Dex::Trace.start(actor: { type: :user, id: 7 }, trace_id: Dex::Id.generate("tr_")) do
      refute_equal original_trace_id, Dex::Trace.trace_id
      original.publish(sync: true)
    end

    assert_equal original_trace_id, seen_trace_id
    assert_equal original_trace_id, child.trace_id
    assert_equal original.id, child.caused_by_id
  end

  def test_trace_id_inherited_through_chain
    root_class = build_event do
      prop :n, Integer
    end

    root = root_class.new(n: 0)
    events = [root]

    Dex::Event::Trace.with_event(root) do
      e1 = root_class.new(n: 1)
      events << e1
      Dex::Event::Trace.with_event(e1) do
        e2 = root_class.new(n: 2)
        events << e2
      end
    end

    assert events.all? { |e| e.trace_id == root.trace_id }
  end

  def test_no_trace_context_by_default
    assert_nil Dex::Event::Trace.current_event_id
    assert_nil Dex::Event::Trace.current_trace_id
    assert_equal [], Dex::Trace.current
  end

  def test_dump_and_restore
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "original")
    dumped = nil

    Dex::Event::Trace.with_event(event) do
      dumped = Dex::Event::Trace.dump
    end

    assert_equal event.trace_id, dumped[:trace_id]
    assert_equal event.id, dumped.dig(:event_context, :id)

    inner_child = nil
    Dex::Event::Trace.restore(dumped) do
      inner_child = event_class.new(name: "restored")
    end

    assert_equal event.id, inner_child.caused_by_id
    assert_equal event.trace_id, inner_child.trace_id

    # Restore nil is a noop
    Dex::Event::Trace.restore(nil) do
      noop_event = event_class.new(name: "test")
      assert_nil noop_event.caused_by_id
    end
  end

  def test_clear
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    Dex::Event::Trace.with_event(event) do
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

  def test_legacy_restore_shape
    event_class = build_event do
      prop :name, String
    end

    parent = event_class.new(name: "parent")
    child = nil

    # Legacy shape still works
    Dex::Event::Trace.restore(id: parent.id, trace_id: parent.trace_id) do
      child = event_class.new(name: "child")
    end

    assert_equal parent.id, child.caused_by_id
    assert_equal parent.trace_id, child.trace_id

    # Preserves active trace frames
    actor = nil
    child2 = nil

    Dex::Trace.start(actor: { type: :user, id: 7 }) do
      Dex::Event::Trace.restore(id: parent.id, trace_id: parent.trace_id) do
        actor = Dex::Trace.actor
        child2 = event_class.new(name: "child2")
      end
    end

    assert_equal "user", actor[:actor_type]
    assert_equal "7", actor[:id]
    assert_equal parent.id, child2.caused_by_id
    assert_equal parent.trace_id, child2.trace_id
  end
end
