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
    assert_equal [], event.event_ancestry
    assert_nil event.caused_by_id
  end

  def test_id_generation
    event_class = build_event { prop :name, String }

    event = event_class.new(name: "test")
    # Prefixed format
    assert_match(/\Aev_[1-9A-HJ-NP-Za-km-z]{20}\z/, event.id)
    # trace_id is separate from id
    assert_match(/\Atr_[1-9A-HJ-NP-Za-km-z]{20}\z/, event.trace_id)
    refute_equal event.id, event.trace_id

    # Each event gets unique id
    ids = 10.times.map { event_class.new(name: "test").id }
    assert_equal 10, ids.uniq.size
  end

  def test_timestamp_is_utc
    event_class = build_event do
      prop :name, String
    end

    event = event_class.new(name: "test")
    assert_instance_of Time, event.timestamp
    assert event.timestamp.utc?
  end

  def test_reserved_prop_names_raise
    %i[id timestamp trace_id caused_by_id caused_by event_ancestry context publish metadata sync].each do |name|
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
    assert_equal [], json["metadata"]["event_ancestry"]
  end

  def test_context_capture
    # From config
    ctx_value = { user_id: 7 }
    Dex.configure { |c| c.event_context = -> { ctx_value } }
    event_class = build_event { prop :name, String }
    event = event_class.new(name: "test")
    assert_equal ctx_value, event.context
    Dex.configure { |c| c.event_context = nil }

    # Nil by default
    event = event_class.new(name: "test")
    assert_nil event.context

    # Failure returns nil
    Dex.configure { |c| c.event_context = -> { raise "boom" } }
    event = event_class.new(name: "test")
    assert_nil event.context
  ensure
    Dex.configure { |c| c.event_context = nil }
  end

  def test_uses_active_trace_id_when_present
    event_class = build_event do
      prop :name, String
    end

    event = nil

    Dex::Trace.start(actor: { type: :user, id: 7 }) do
      trace_id = Dex::Trace.trace_id
      event = event_class.new(name: "test")
      assert_equal trace_id, event.trace_id
    end
  end
end
