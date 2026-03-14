# frozen_string_literal: true

require "test_helper"

class TestEventRegistry < Minitest::Test
  # --- Event registry ---

  def test_event_registration
    result = Dex::Event.registry
    assert_instance_of Set, result
    assert result.frozen?

    define_event(:RegistryTestEvent) { prop :name, String }
    assert_includes Dex::Event.registry, RegistryTestEvent

    anon = build_event { prop :name, String }
    refute_includes Dex::Event.registry, anon

    Dex::Event.deregister(RegistryTestEvent)
    refute_includes Dex::Event.registry, RegistryTestEvent
  end

  # --- Event description ---

  def test_event_description
    ev = build_event do
      description "Something happened"
      prop :name, String
    end
    assert_equal "Something happened", ev.description

    ev_nil = build_event { prop :name, String }
    assert_nil ev_nil.description
  end

  # --- Event to_h ---

  def test_event_to_h
    ev = define_event(:ExportEvent) do
      description "Test event"
      prop :name, String, desc: "The name"
      prop :count, Integer
    end
    h = ev.to_h
    assert_equal "ExportEvent", h[:name]
    assert_equal "Test event", h[:description]
    assert_equal "String", h[:props][:name][:type]
    assert_equal "The name", h[:props][:name][:desc]
    assert h[:props][:name][:required]

    # Omits description when nil
    ev_nil = build_event { prop :x, Integer }
    refute ev_nil.to_h.key?(:description)
  end

  # --- Event to_json_schema ---

  def test_event_to_json_schema
    ev = define_event(:SchemaEvent) do
      description "Schema test"
      prop :order_id, Integer
      prop? :note, String
    end
    schema = ev.to_json_schema
    assert_equal "https://json-schema.org/draft/2020-12/schema", schema[:$schema]
    assert_equal "SchemaEvent", schema[:title]
    assert_equal "Schema test", schema[:description]
    assert_equal "object", schema[:type]
    assert_equal({ type: "integer" }, schema[:properties]["order_id"])
    assert_includes schema[:required], "order_id"
    refute_includes(schema[:required] || [], "note")
    assert_equal false, schema[:additionalProperties]
  end

  # --- Event export ---

  def test_event_export
    define_event(:ExportEvA) { prop :x, Integer }
    define_event(:ExportEvB) { prop :y, String }

    result = Dex::Event.export
    names = result.map { |h| h[:name] }
    assert_includes names, "ExportEvA"
    assert_includes names, "ExportEvB"
    assert names.index("ExportEvA") < names.index("ExportEvB")

    # JSON schema format
    schema_result = Dex::Event.export(format: :json_schema)
    entry = schema_result.find { |h| h[:title] == "ExportEvA" }
    assert entry
    assert entry.key?(:properties)
  end

  # --- Handler registry ---

  def test_handler_registration
    result = Dex::Event::Handler.registry
    assert_instance_of Set, result
    assert result.frozen?

    define_event(:HandlerRegEvent) { prop :x, Integer }
    define_handler(:HandlerRegTestHandler) do
      on HandlerRegEvent
      def perform = nil
    end
    assert_includes Dex::Event::Handler.registry, HandlerRegTestHandler

    anon = build_handler { def perform = nil }
    refute_includes Dex::Event::Handler.registry, anon
  end

  # --- Handler to_h ---

  def test_handler_to_h
    define_event(:HandlerExportEvent) { prop :x, Integer }
    define_handler(:HandlerExportTest) do
      on HandlerExportEvent
      retries 3
      transaction false
      def perform = nil
    end
    h = HandlerExportTest.to_h
    assert_equal "HandlerExportTest", h[:name]
    assert_equal ["HandlerExportEvent"], h[:events]
    assert_equal 3, h[:retries]
    refute h[:transaction]
    assert_instance_of Array, h[:pipeline]

    # Without event
    define_handler(:HandlerNoEvent) { def perform = nil }
    h_no = HandlerNoEvent.to_h
    assert_equal "HandlerNoEvent", h_no[:name]
    refute h_no.key?(:events)

    # Multi-event
    define_event(:MultiEvA) { prop :x, Integer }
    define_event(:MultiEvB) { prop :y, String }
    define_handler(:MultiHandler) do
      on MultiEvA, MultiEvB
      def perform = nil
    end
    assert_equal [MultiEvA, MultiEvB], MultiHandler.handled_events
    assert_equal %w[MultiEvA MultiEvB], MultiHandler.to_h[:events]
  end

  # --- Handler export ---

  def test_handler_export
    define_event(:HandlerBulkEvent) { prop :x, Integer }
    define_handler(:HandlerBulkA) do
      on HandlerBulkEvent
      def perform = nil
    end

    result = Dex::Event::Handler.export
    names = result.map { |h| h[:name] }
    assert_includes names, "HandlerBulkA"

    assert_raises(ArgumentError) { Dex::Event::Handler.export(format: :xml) }
  end

  def test_handler_deregister_unsubscribes_from_bus
    define_event(:DeregBusEvent) { prop :x, Integer }
    define_handler(:DeregBusHandler) do
      on DeregBusEvent
      def perform = nil
    end
    assert_includes Dex::Event::Bus.subscribers_for(DeregBusEvent), DeregBusHandler
    Dex::Event::Handler.deregister(DeregBusHandler)
    refute_includes Dex::Event::Bus.subscribers_for(DeregBusEvent), DeregBusHandler
  end
end
