# frozen_string_literal: true

require "test_helper"

class TestEventRegistry < Minitest::Test
  # --- Event registry ---

  def test_event_registry_returns_frozen_set
    result = Dex::Event.registry
    assert_instance_of Set, result
    assert result.frozen?
  end

  def test_named_event_registered
    define_event(:RegistryTestEvent) { prop :name, String }
    assert_includes Dex::Event.registry, RegistryTestEvent
  end

  def test_anonymous_event_excluded
    ev = build_event { prop :name, String }
    refute_includes Dex::Event.registry, ev
  end

  def test_event_deregister
    define_event(:DeregEvent) { prop :x, Integer }
    assert_includes Dex::Event.registry, DeregEvent
    Dex::Event.deregister(DeregEvent)
    refute_includes Dex::Event.registry, DeregEvent
  end

  # --- Event description ---

  def test_event_description
    ev = build_event do
      description "Something happened"
      prop :name, String
    end
    assert_equal "Something happened", ev.description
  end

  def test_event_description_nil_by_default
    ev = build_event { prop :name, String }
    assert_nil ev.description
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
  end

  def test_event_to_h_omits_description_when_nil
    ev = build_event { prop :x, Integer }
    h = ev.to_h
    refute h.key?(:description)
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
    idx_a = names.index("ExportEvA")
    idx_b = names.index("ExportEvB")
    assert idx_a < idx_b
  end

  def test_event_export_json_schema
    define_event(:ExportEvSchema) { prop :x, Integer }
    result = Dex::Event.export(format: :json_schema)
    entry = result.find { |h| h[:title] == "ExportEvSchema" }
    assert entry
    assert entry.key?(:properties)
  end

  # --- Handler registry ---

  def test_handler_registry_returns_frozen_set
    result = Dex::Event::Handler.registry
    assert_instance_of Set, result
    assert result.frozen?
  end

  def test_named_handler_registered
    define_event(:HandlerRegEvent) { prop :x, Integer }
    define_handler(:HandlerRegTestHandler) do
      on HandlerRegEvent
      def perform = nil
    end
    assert_includes Dex::Event::Handler.registry, HandlerRegTestHandler
  end

  def test_anonymous_handler_excluded
    h = build_handler { def perform = nil }
    refute_includes Dex::Event::Handler.registry, h
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
  end

  def test_handler_to_h_without_event
    define_handler(:HandlerNoEvent) { def perform = nil }
    h = HandlerNoEvent.to_h
    assert_equal "HandlerNoEvent", h[:name]
    refute h.key?(:events)
  end

  def test_handler_multi_event
    define_event(:MultiEvA) { prop :x, Integer }
    define_event(:MultiEvB) { prop :y, String }
    define_handler(:MultiHandler) do
      on MultiEvA, MultiEvB
      def perform = nil
    end
    assert_equal [MultiEvA, MultiEvB], MultiHandler.handled_events
    h = MultiHandler.to_h
    assert_equal %w[MultiEvA MultiEvB], h[:events]
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
  end

  def test_handler_export_unknown_format
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
