# frozen_string_literal: true

require "test_helper"

class TestEventPublishing < Minitest::Test
  def test_instance_publish_sync
    event_class = build_event do
      prop :order_id, Integer
    end

    received = []
    build_handler do
      on event_class
      define_method(:perform) { received << event }
    end

    event = event_class.new(order_id: 1)
    event.publish(sync: true)

    assert_equal 1, received.size
    assert_equal 1, received.first.order_id
  end

  def test_class_publish_sync
    define_event(:TestClassPubEvent) do
      prop :order_id, Integer
    end

    received = []
    define_handler(:TestClassPubHandler) do
      on TestClassPubEvent
      define_method(:perform) { received << event }
    end

    TestClassPubEvent.publish(order_id: 1, sync: true)

    assert_equal 1, received.size
    assert_equal 1, received.first.order_id
  end

  def test_class_publish_with_caused_by
    parent_class = define_event(:ParentPubEvent) do
      prop :name, String
    end

    define_event(:ChildPubEvent) do
      prop :value, Integer
    end

    received = []
    define_handler(:ChildPubHandler) do
      on ChildPubEvent
      define_method(:perform) { received << event }
    end

    parent = parent_class.new(name: "parent")
    ChildPubEvent.publish(value: 42, caused_by: parent, sync: true)

    assert_equal 1, received.size
    assert_equal parent.id, received.first.caused_by_id
    assert_equal parent.trace_id, received.first.trace_id
  end

  def test_publish_with_no_handlers
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "lonely")
    event.publish(sync: true)
  end

  def test_publish_fans_out_to_multiple_handlers
    event_class = build_event do
      prop :n, Integer
    end

    calls = []

    build_handler do
      on event_class
      define_method(:perform) { calls << :first }
    end

    build_handler do
      on event_class
      define_method(:perform) { calls << :second }
    end

    event_class.new(n: 1).publish(sync: true)
    assert_equal %i[first second], calls
  end

  def test_async_reconstruction_coerces_ref_type
    setup_test_database
    model = TestModel.create!(name: "Alice")

    define_event(:TestRefCoerceEvent) do
      prop :model, _Ref(TestModel)
    end

    received = []
    define_handler(:TestRefCoerceHandler) do
      on TestRefCoerceEvent
      define_method(:perform) { received << event }
    end

    Dex::Event::Processor.new.perform(
      handler_class: "TestRefCoerceHandler",
      event_class: "TestRefCoerceEvent",
      payload: { "model" => model.id },
      metadata: build_event_metadata
    )

    assert_equal 1, received.size
    assert_instance_of TestModel, received.first.model
    assert_equal model.id, received.first.model.id
  end

  def test_async_reconstruction_coerces_date
    define_event(:TestDateCoerceEvent) do
      prop :due, Date
    end

    received = []
    define_handler(:TestDateCoerceHandler) do
      on TestDateCoerceEvent
      define_method(:perform) { received << event }
    end

    Dex::Event::Processor.new.perform(
      handler_class: "TestDateCoerceHandler",
      event_class: "TestDateCoerceEvent",
      payload: { "due" => "2025-06-15" },
      metadata: build_event_metadata
    )

    assert_equal 1, received.size
    assert_equal Date.new(2025, 6, 15), received.first.due
  end

  include ActiveJob::TestHelper

  def test_async_enqueue_resolves_processor
    define_event(:TestAsyncEnqueueEvent) do
      prop :n, Integer
    end

    define_handler(:TestAsyncEnqueueHandler) do
      on TestAsyncEnqueueEvent
      def perform
      end
    end

    event = TestAsyncEnqueueEvent.new(n: 1)
    trace_data = { id: event.id, trace_id: event.trace_id }

    assert_enqueued_with(job: Dex::Event::Processor) do
      Dex::Event::Bus.send(:_event_bus_enqueue, TestAsyncEnqueueHandler, event, trace_data)
    end
  end

  def test_async_reconstruction_coerces_array_ref
    setup_test_database
    m1 = TestModel.create!(name: "Alice")
    m2 = TestModel.create!(name: "Bob")

    define_event(:TestArrayRefEvent) do
      prop :models, _Array(_Ref(TestModel))
    end

    received = []
    define_handler(:TestArrayRefHandler) do
      on TestArrayRefEvent
      define_method(:perform) { received << event }
    end

    Dex::Event::Processor.new.perform(
      handler_class: "TestArrayRefHandler",
      event_class: "TestArrayRefEvent",
      payload: { "models" => [m1.id, m2.id] },
      metadata: build_event_metadata
    )

    assert_equal 1, received.size
    assert_equal [m1.id, m2.id], received.first.models.map(&:id)
  end

  def test_array_ref_serialization
    setup_test_database
    m1 = TestModel.create!(name: "Alice")
    m2 = TestModel.create!(name: "Bob")

    event_class = build_event do
      prop :models, _Array(_Ref(TestModel))
    end

    event = event_class.new(models: [m1, m2])
    json = event._props_as_json

    assert_equal [m1.id, m2.id], json["models"]
  end

  def test_async_reconstruction_coerces_symbol
    define_event(:TestSymCoerceEvent) do
      prop :status, Symbol
    end

    received = []
    define_handler(:TestSymCoerceHandler) do
      on TestSymCoerceEvent
      define_method(:perform) { received << event }
    end

    Dex::Event::Processor.new.perform(
      handler_class: "TestSymCoerceHandler",
      event_class: "TestSymCoerceEvent",
      payload: { "status" => "active" },
      metadata: build_event_metadata
    )

    assert_equal 1, received.size
    assert_equal :active, received.first.status
  end
end
