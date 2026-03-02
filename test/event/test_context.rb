# frozen_string_literal: true

require "test_helper"

class TestEventContext < Minitest::Test
  def test_context_captured_at_event_creation
    Dex.configure { |c| c.event_context = -> { { user_id: 1 } } }

    event_class = build_event do
      prop :n, Integer
    end

    event = event_class.new(n: 1)
    assert_equal({ user_id: 1 }, event.context)
  ensure
    Dex.configure { |c| c.event_context = nil }
  end

  def test_context_included_in_as_json
    Dex.configure { |c| c.event_context = -> { { tenant: "acme" } } }

    event_class = build_event do
      prop :n, Integer
    end

    event = event_class.new(n: 1)
    json = event.as_json

    assert_equal({ tenant: "acme" }, json["metadata"]["context"])
  ensure
    Dex.configure { |c| c.event_context = nil }
  end

  def test_context_not_in_metadata_when_nil
    event_class = build_event do
      prop :n, Integer
    end

    event = event_class.new(n: 1)
    refute event.metadata.as_json.key?("context")
  end

  def test_restore_event_context_called_in_processor
    restored_context = nil
    Dex.configure do |c|
      c.restore_event_context = ->(ctx) { restored_context = ctx }
    end

    define_event(:TestRestoreCtxEvent) do
      prop :n, Integer
    end

    define_handler(:TestRestoreCtxHandler) do
      on TestRestoreCtxEvent
      def perform
      end
    end

    ctx = { "user_id" => 5 }
    Dex::Event::Processor.new.perform(
      handler_class: "TestRestoreCtxHandler",
      event_class: "TestRestoreCtxEvent",
      payload: { "n" => 1 },
      metadata: build_event_metadata,
      context: ctx
    )

    assert_equal ctx, restored_context
  ensure
    Dex.configure { |c| c.restore_event_context = nil }
  end

  def test_restore_context_failure_does_not_halt_handler
    Dex.configure do |c|
      c.restore_event_context = ->(_ctx) { raise "boom" }
    end

    define_event(:TestRestoreFailEvent) do
      prop :n, Integer
    end

    performed = false
    define_handler(:TestRestoreFailHandler) do
      on TestRestoreFailEvent
      define_method(:perform) { performed = true }
    end

    Dex::Event::Processor.new.perform(
      handler_class: "TestRestoreFailHandler",
      event_class: "TestRestoreFailEvent",
      payload: { "n" => 1 },
      metadata: build_event_metadata,
      context: { "user_id" => 1 }
    )

    assert performed
  ensure
    Dex.configure { |c| c.restore_event_context = nil }
  end
end
