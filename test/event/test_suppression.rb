# frozen_string_literal: true

require "test_helper"

class TestEventSuppression < Minitest::Test
  def test_suppress_all
    event_class = build_event do
      prop :n, Integer
    end

    received = []
    build_handler do
      on event_class
      define_method(:perform) { received << event }
    end

    Dex::Event.suppress do
      event_class.new(n: 1).publish(sync: true)
    end

    assert_empty received
  end

  def test_suppress_specific_class
    event_a = build_event do
      prop :a, Integer
    end

    event_b = build_event do
      prop :b, Integer
    end

    received = []

    build_handler do
      on event_a
      define_method(:perform) { received << [:a, event] }
    end

    build_handler do
      on event_b
      define_method(:perform) { received << [:b, event] }
    end

    Dex::Event.suppress(event_a) do
      event_a.new(a: 1).publish(sync: true)
      event_b.new(b: 2).publish(sync: true)
    end

    assert_equal 1, received.size
    assert_equal :b, received.first.first
  end

  def test_suppress_restores_after_block
    event_class = build_event do
      prop :n, Integer
    end

    received = []
    build_handler do
      on event_class
      define_method(:perform) { received << event }
    end

    Dex::Event.suppress {}
    event_class.new(n: 1).publish(sync: true)

    assert_equal 1, received.size
  end

  def test_nested_suppression
    event_a = build_event do
      prop :a, Integer
    end

    event_b = build_event do
      prop :b, Integer
    end

    received = []

    build_handler do
      on event_a
      define_method(:perform) { received << :a }
    end

    build_handler do
      on event_b
      define_method(:perform) { received << :b }
    end

    Dex::Event.suppress(event_a) do
      Dex::Event.suppress(event_b) do
        event_a.new(a: 1).publish(sync: true)
        event_b.new(b: 1).publish(sync: true)
      end
      # Only event_a still suppressed here
      event_b.new(b: 2).publish(sync: true)
    end

    assert_equal [:b], received
  end

  def test_suppress_validates_class
    assert_raises(ArgumentError) do
      Dex::Event.suppress(String) {}
    end
  end

  def test_suppress_validates_non_class_argument
    err = assert_raises(ArgumentError) do
      Dex::Event.suppress(:not_a_class) {}
    end
    assert_match(/not a Dex::Event subclass/, err.message)
  end

  def test_suppress_child_event_class
    parent_class = build_event do
      prop :n, Integer
    end

    child_class = Class.new(parent_class)

    received = []
    build_handler do
      on child_class
      define_method(:perform) { received << event }
    end

    Dex::Event.suppress(parent_class) do
      child_class.new(n: 1).publish(sync: true)
    end

    assert_empty received
  end
end
