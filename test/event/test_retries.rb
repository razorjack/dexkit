# frozen_string_literal: true

require "test_helper"

class TestEventRetries < Minitest::Test
  include ActiveJob::TestHelper

  def test_retries_exponential_backoff
    define_event(:TestRetryExpEvent) do
      prop :n, Integer
    end

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
  end

  def test_retries_fixed_wait
    define_event(:TestRetryFixedEvent) do
      prop :n, Integer
    end

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
  end

  def test_retries_proc_wait
    define_event(:TestRetryProcEvent) do
      prop :n, Integer
    end

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

  def test_retries_exhausted_raises
    define_event(:TestRetryExhaustEvent) do
      prop :n, Integer
    end

    define_handler(:TestRetryExhaustHandler) do
      on TestRetryExhaustEvent
      retries 2
      define_method(:perform) { raise "boom" }
    end

    # retries 2 means 2 retries (3 total attempts): original + retry 1 + retry 2
    # attempt_number 3 is past all retries, so it should raise
    assert_raises(RuntimeError) do
      Dex::Event::Processor.new.perform(
        handler_class: "TestRetryExhaustHandler",
        event_class: "TestRetryExhaustEvent",
        payload: { "n" => 1 },
        metadata: build_event_metadata,
        attempt_number: 3
      )
    end
  end

  def test_last_retry_still_retries
    define_event(:TestLastRetryEvent) do
      prop :n, Integer
    end

    define_handler(:TestLastRetryHandler) do
      on TestLastRetryEvent
      retries 2
      define_method(:perform) { raise "boom" }
    end

    # attempt_number 2 is the last retry — should still enqueue
    assert_enqueued_with(job: Dex::Event::Processor) do
      Dex::Event::Processor.new.perform(
        handler_class: "TestLastRetryHandler",
        event_class: "TestLastRetryEvent",
        payload: { "n" => 1 },
        metadata: build_event_metadata,
        attempt_number: 2
      )
    rescue RuntimeError
      nil
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
