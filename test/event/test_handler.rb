# frozen_string_literal: true

require "test_helper"

class TestEventHandler < Minitest::Test
  def test_on_registers_subscription
    event_class = build_event do
      prop :name, String
    end

    handler = build_handler do
      on event_class
      def perform
      end
    end

    subs = Dex::Event::Bus.subscribers_for(event_class)
    assert_includes subs, handler
  end

  def test_on_multiple_events
    event_a = build_event do
      prop :a, Integer
    end

    event_b = build_event do
      prop :b, Integer
    end

    handler = build_handler do
      on event_a, event_b
      def perform
      end
    end

    assert_includes Dex::Event::Bus.subscribers_for(event_a), handler
    assert_includes Dex::Event::Bus.subscribers_for(event_b), handler
  end

  def test_on_validates_event_class
    assert_raises(ArgumentError) do
      build_handler do
        on String
      end
    end
  end

  def test_on_validates_non_class_argument
    err = assert_raises(ArgumentError) do
      build_handler do
        on :not_a_class
      end
    end
    assert_match(/not a Dex::Event subclass/, err.message)
  end

  def test_perform_required
    handler = build_handler
    instance = handler.new

    assert_raises(NotImplementedError) { instance.send(:perform) }
  end

  def test_perform_is_private
    handler = build_handler do
      def perform
      end
    end

    refute handler.public_method_defined?(:perform)
    assert handler.private_method_defined?(:perform)
  end

  def test_event_accessor
    event_class = build_event do
      prop :name, String
    end

    received_event = nil
    build_handler do
      on event_class
      define_method(:perform) { received_event = event }
    end

    event_class.new(name: "hello").publish(sync: true)
    assert_equal "hello", received_event.name
  end

  def test_retries_validation_positive_integer
    assert_raises(ArgumentError) do
      build_handler do
        retries 0
      end
    end

    assert_raises(ArgumentError) do
      build_handler do
        retries(-1)
      end
    end

    assert_raises(ArgumentError) do
      build_handler do
        retries "three"
      end
    end
  end

  def test_retries_wait_validation
    assert_raises(ArgumentError) do
      build_handler do
        retries 3, wait: "invalid"
      end
    end
  end

  def test_retries_stores_config
    handler = build_handler do
      retries 3, wait: 5
    end

    config = handler._event_handler_retry_config
    assert_equal 3, config[:count]
    assert_equal 5, config[:wait]
  end

  def test_retries_inherits_from_parent
    parent = build_handler do
      retries 3
    end

    child = Class.new(parent)

    assert_equal 3, child._event_handler_retry_config[:count]
  end

  def test_retries_with_proc_wait
    handler = build_handler do
      retries 5, wait: ->(attempt) { attempt * 2 }
    end

    config = handler._event_handler_retry_config
    assert_equal 5, config[:count]
    assert_instance_of Proc, config[:wait]
  end
end
