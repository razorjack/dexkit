# frozen_string_literal: true

require "test_helper"

class TestEventRetries < Minitest::Test
  include ActiveJob::TestHelper

  def test_retries_enqueue_with_wait_strategies
    # Exponential backoff (default)
    define_event(:TestRetryExpEvent) { prop :n, Integer }
    define_handler(:TestRetryExpHandler) do
      on TestRetryExpEvent
      retries 3
      define_method(:perform) { raise "boom" }
    end

    assert_enqueued_with(job: Dex::Event::Processor) do
      Dex::Event::Processor.new.perform(
        handler_class: "TestRetryExpHandler",
        event_class: "TestRetryExpEvent",
        payload: { "n" => 1 },
        metadata: build_event_metadata,
        attempt_number: 1
      )
    rescue RuntimeError
      nil
    end

    # Fixed wait
    define_event(:TestRetryFixedEvent) { prop :n, Integer }
    define_handler(:TestRetryFixedHandler) do
      on TestRetryFixedEvent
      retries 3, wait: 10
      define_method(:perform) { raise "boom" }
    end

    assert_enqueued_with(job: Dex::Event::Processor) do
      Dex::Event::Processor.new.perform(
        handler_class: "TestRetryFixedHandler",
        event_class: "TestRetryFixedEvent",
        payload: { "n" => 1 },
        metadata: build_event_metadata,
        attempt_number: 1
      )
    rescue RuntimeError
      nil
    end

    # Proc wait
    define_event(:TestRetryProcEvent) { prop :n, Integer }
    define_handler(:TestRetryProcHandler) do
      on TestRetryProcEvent
      retries 3, wait: ->(attempt) { attempt * 5 }
      define_method(:perform) { raise "boom" }
    end

    assert_enqueued_with(job: Dex::Event::Processor) do
      Dex::Event::Processor.new.perform(
        handler_class: "TestRetryProcHandler",
        event_class: "TestRetryProcEvent",
        payload: { "n" => 1 },
        metadata: build_event_metadata,
        attempt_number: 1
      )
    rescue RuntimeError
      nil
    end
  end

  def test_retries_boundary
    define_event(:TestRetryBoundaryEvent) { prop :n, Integer }
    define_handler(:TestRetryBoundaryHandler) do
      on TestRetryBoundaryEvent
      retries 2
      define_method(:perform) { raise "boom" }
    end

    # Last retry (attempt 2) still enqueues
    assert_enqueued_with(job: Dex::Event::Processor) do
      Dex::Event::Processor.new.perform(
        handler_class: "TestRetryBoundaryHandler",
        event_class: "TestRetryBoundaryEvent",
        payload: { "n" => 1 },
        metadata: build_event_metadata,
        attempt_number: 2
      )
    rescue RuntimeError
      nil
    end

    # Exhausted (attempt 3) raises
    assert_raises(RuntimeError) do
      Dex::Event::Processor.new.perform(
        handler_class: "TestRetryBoundaryHandler",
        event_class: "TestRetryBoundaryEvent",
        payload: { "n" => 1 },
        metadata: build_event_metadata,
        attempt_number: 3
      )
    end
  end

  def test_no_retries_raises_immediately
    define_event(:TestNoRetryEvent) do
      prop :n, Integer
    end

    define_handler(:TestNoRetryHandler) do
      on TestNoRetryEvent
      define_method(:perform) { raise "boom" }
    end

    assert_raises(RuntimeError) do
      Dex::Event::Processor.new.perform(
        handler_class: "TestNoRetryHandler",
        event_class: "TestNoRetryEvent",
        payload: { "n" => 1 },
        metadata: build_event_metadata
      )
    end
  end
end
