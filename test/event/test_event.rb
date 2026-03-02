# frozen_string_literal: true

require "test_helper"

class TestEvent < Minitest::Test
  def test_defines_props
    event_class = build_event do
      prop :order_id, Integer
      prop :total, Float
    end

    event = event_class.new(order_id: 1, total: 99.99)
    assert_equal 1, event.order_id
    assert_equal 99.99, event.total
  end

  def test_optional_props
    event_class = build_event do
      prop :order_id, Integer
      prop? :note, String
    end

    event = event_class.new(order_id: 1)
    assert_equal 1, event.order_id
    assert_nil event.note
  end

  def test_frozen_after_creation
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert event.frozen?
  end

  def test_metadata_auto_generated
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_instance_of Dex::Event::Metadata, event.metadata
    refute_nil event.id
    refute_nil event.timestamp
    refute_nil event.trace_id
  end

  def test_id_is_uuid
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, event.id)
  end

  def test_timestamp_is_utc
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_instance_of Time, event.timestamp
    assert event.timestamp.utc?
  end

  def test_trace_id_defaults_to_id_when_no_trace
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_equal event.id, event.trace_id
  end

  def test_caused_by_id_nil_by_default
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_nil event.caused_by_id
  end

  def test_reserved_prop_names_raise
    %i[id timestamp trace_id caused_by_id caused_by context publish metadata sync].each do |name|
      assert_raises(ArgumentError) do
        build_event do
          prop name, String
        end
      end
    end
  end

  def test_invalid_props_raise_literal_type_error
    event_class = build_event do
      prop :count, Integer
    end

    assert_raises(Literal::TypeError) { event_class.new(count: "not_an_int") }
  end

  def test_as_json_serialization
    event_class = define_event(:TestJsonEvent) do
      prop :order_id, Integer
      prop? :note, String
    end

    event = event_class.new(order_id: 42, note: "rush")
    json = event.as_json

    assert_equal "TestJsonEvent", json["type"]
    assert_equal({ "order_id" => 42, "note" => "rush" }, json["payload"])
    assert_equal event.id, json["metadata"]["id"]
    assert_equal event.trace_id, json["metadata"]["trace_id"]
  end

  def test_context_from_config
    ctx_value = { user_id: 7 }
    Dex.configure { |c| c.event_context = -> { ctx_value } }

    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_equal ctx_value, event.context
  ensure
    Dex.configure { |c| c.event_context = nil }
  end

  def test_context_nil_by_default
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_nil event.context
  end

  def test_context_failure_returns_nil
    Dex.configure { |c| c.event_context = -> { raise "boom" } }

    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_nil event.context
  ensure
    Dex.configure { |c| c.event_context = nil }
  end

  def test_each_event_gets_unique_id
    event_class = build_event do
      prop :n, Integer
    end

    ids = 10.times.map { event_class.new(n: 1).id }
    assert_equal 10, ids.uniq.size
  end
end
