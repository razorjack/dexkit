# frozen_string_literal: true

require "test_helper"

class TestEventBus < Minitest::Test
  def test_subscribe_and_lookup
    event_class = build_event do
      prop :name, String
    end

    handler = build_handler do
      def perform
      end
    end

    Dex::Event::Bus.subscribe(event_class, handler)
    assert_includes Dex::Event::Bus.subscribers_for(event_class), handler
  end

  def test_subscribe_is_idempotent
    event_class = build_event do
      prop :name, String
    end

    handler = build_handler do
      def perform
      end
    end

    Dex::Event::Bus.subscribe(event_class, handler)
    Dex::Event::Bus.subscribe(event_class, handler)

    subs = Dex::Event::Bus.subscribers_for(event_class)
    assert_equal 1, subs.count { |s| s == handler }
  end

  def test_unsubscribe
    event_class = build_event do
      prop :name, String
    end

    handler = build_handler do
      def perform
      end
    end

    Dex::Event::Bus.subscribe(event_class, handler)
    Dex::Event::Bus.unsubscribe(event_class, handler)
    assert_empty Dex::Event::Bus.subscribers_for(event_class)
  end

  def test_inheritance_matching
    parent_event = build_event do
      prop :name, String
    end

    child_event = Class.new(parent_event)

    handler = build_handler do
      def perform
      end
    end

    Dex::Event::Bus.subscribe(parent_event, handler)
    assert_includes Dex::Event::Bus.subscribers_for(child_event), handler
  end

  def test_clear_removes_all
    event_class = build_event do
      prop :name, String
    end

    handler = build_handler do
      def perform
      end
    end

    Dex::Event::Bus.subscribe(event_class, handler)
    Dex::Event::Bus.clear!
    assert_empty Dex::Event::Bus.subscribers_for(event_class)
  end

  def test_subscribe_validates_event_argument
    handler = build_handler { def perform = nil }

    assert_raises(ArgumentError) { Dex::Event::Bus.subscribe(String, handler) }

    err = assert_raises(ArgumentError) { Dex::Event::Bus.subscribe(:not_a_class, handler) }
    assert_match(/not a Dex::Event subclass/, err.message)
  end

  def test_subscribe_validates_handler_argument
    event_class = build_event { prop :name, String }

    assert_raises(ArgumentError) { Dex::Event::Bus.subscribe(event_class, String) }

    err = assert_raises(ArgumentError) { Dex::Event::Bus.subscribe(event_class, "not_a_class") }
    assert_match(/not a Dex::Event::Handler subclass/, err.message)
  end

  def test_fan_out_to_multiple_handlers
    event_class = build_event do
      prop :n, Integer
    end

    calls = []

    build_handler do
      on event_class
      define_method(:perform) { calls << :h1 }
    end

    build_handler do
      on event_class
      define_method(:perform) { calls << :h2 }
    end

    event_class.new(n: 1).publish(sync: true)
    assert_includes calls, :h1
    assert_includes calls, :h2
  end
end
