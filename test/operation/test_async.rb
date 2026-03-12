# frozen_string_literal: true

require "test_helper"

class TestOperationAsync < Minitest::Test
  include ActiveJob::TestHelper

  def setup
    setup_test_database
  end

  def test_async_returns_proxy
    op = build_async_operation.new(name: "Test")
    proxy = op.async

    assert_instance_of Dex::Operation::AsyncProxy, proxy
  end

  def test_async_perform_enqueues_job
    op = build_async_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job) do
      op.async.call
    end
  end

  def test_job_executes_operation
    spy = Minitest::Mock.new
    spy.expect :call, nil, ["Test"]

    operation(name: :TestSpyOperation, params: { name: String, spy: Object }) do
      spy.call(name)
    end

    # Directly test the job execution (avoids Rails 8 tagged_logger issues)
    Dex::Operation::Job.new.perform(class_name: "TestSpyOperation", params: { name: "Test", spy: spy })

    assert_mock spy
  end

  def test_async_with_queue
    op = build_async_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job, queue: "low") do
      op.async(queue: "low").call
    end
  end

  def test_async_with_delay
    freeze_time = Time.now
    Time.stub :now, freeze_time do
      op = build_async_operation.new(name: "Test")

      assert_enqueued_with(job: Dex::Operation::Job) do
        op.async(in: 300).call # 5 minutes in seconds
      end
    end
  end

  def test_async_with_scheduled_time
    scheduled_time = Time.now + 3600 # 1 hour from now
    op = build_async_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job, at: scheduled_time) do
      op.async(at: scheduled_time).call
    end
  end

  def test_class_level_async_sets_defaults
    op_class = build_async_operation do
      async queue: "background"
    end

    assert_enqueued_with(job: Dex::Operation::Job, queue: "background") do
      op_class.new(name: "Test").async.call
    end
  end

  def test_runtime_options_override_class_defaults
    op_class = build_async_operation do
      async queue: "low"
    end

    assert_enqueued_with(job: Dex::Operation::Job, queue: "urgent") do
      op_class.new(name: "Test").async(queue: "urgent").call
    end
  end

  def test_set_async_equivalent_to_shortcut
    op1 = build_async_operation do
      async queue: "low"
    end

    op2 = build_async_operation do
      set :async, queue: "low"
    end

    assert_equal op1.settings_for(:async), op2.settings_for(:async)
  end

  def test_async_with_queue_and_scheduled_time
    scheduled_time = Time.now + 3600
    op = build_async_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job, queue: "low", at: scheduled_time) do
      op.async(queue: "low", at: scheduled_time).call
    end
  end

  def test_async_with_queue_and_delay
    op = build_async_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job, queue: "low") do
      op.async(queue: "low", in: 300).call
    end
  end

  def test_class_defaults_compose_with_runtime_options
    scheduled_time = Time.now + 3600

    op_class = build_async_operation do
      async queue: "low"
    end

    assert_enqueued_with(job: Dex::Operation::Job, queue: "low", at: scheduled_time) do
      op_class.new(name: "Test").async(at: scheduled_time).call
    end
  end

  def test_settings_inheritance_for_async
    parent = build_async_operation do
      set :async, queue: "default", priority: 5
    end

    child = build_async_operation(parent: parent) do
      set :async, priority: 10
    end

    assert_equal({ queue: "default", priority: 10 }, child.settings_for(:async))
  end

  # --- Round-trip serialization tests ---

  def test_async_round_trip_date
    define_operation(:TestDateOp) do
      prop :due, Date
      def perform = due
    end

    result = Dex::Operation::Job.new.perform(
      class_name: "TestDateOp", params: { "due" => "2025-06-15" }
    )

    assert_equal Date.new(2025, 6, 15), result
  end

  def test_async_round_trip_time
    define_operation(:TestTimeOp) do
      prop :at, Time
      def perform = at
    end

    result = Dex::Operation::Job.new.perform(
      class_name: "TestTimeOp", params: { "at" => "2025-06-15 10:30:00 UTC" }
    )

    assert_instance_of Time, result
    assert_equal 2025, result.year
    assert_equal 6, result.month
    assert_equal 15, result.day
  end

  def test_async_round_trip_symbol
    define_operation(:TestSymbolOp) do
      prop :status, Symbol
      def perform = status
    end

    result = Dex::Operation::Job.new.perform(
      class_name: "TestSymbolOp", params: { "status" => "active" }
    )

    assert_equal :active, result
  end

  def test_async_round_trip_optional_date_nil
    define_operation(:TestOptDateNilOp) do
      prop? :due, Date
      def perform = due
    end

    result = Dex::Operation::Job.new.perform(
      class_name: "TestOptDateNilOp", params: { "due" => nil }
    )

    assert_nil result
  end

  def test_async_round_trip_optional_date_present
    define_operation(:TestOptDateOp) do
      prop? :due, Date
      def perform = due
    end

    result = Dex::Operation::Job.new.perform(
      class_name: "TestOptDateOp", params: { "due" => "2025-06-15" }
    )

    assert_equal Date.new(2025, 6, 15), result
  end

  def test_async_round_trip_array_of_dates
    define_operation(:TestArrayDatesOp) do
      prop :dates, _Array(Date)
      def perform = dates
    end

    result = Dex::Operation::Job.new.perform(
      class_name: "TestArrayDatesOp", params: { "dates" => ["2025-01-01", "2025-12-31"] }
    )

    assert_equal [Date.new(2025, 1, 1), Date.new(2025, 12, 31)], result
  end

  def test_async_round_trip_record
    model = TestModel.create!(name: "Alice")

    define_operation(:TestRecordOp) do
      prop :model, _Ref(TestModel)
      def perform = model
    end

    result = Dex::Operation::Job.new.perform(
      class_name: "TestRecordOp", params: { "model" => model.id }
    )

    assert_equal model, result
  end

  def test_async_job_restores_trace_context
    seen = nil

    define_operation(:AsyncTraceChild) do
      prop :name, String

      define_method(:perform) do
        seen = {
          trace_id: Dex::Trace.trace_id,
          actor: Dex::Trace.actor,
          classes: Dex::Trace.current.map { |frame| frame[:class] }.compact
        }
      end
    end

    define_operation(:AsyncTraceParent) do
      prop :name, String

      def perform
        AsyncTraceChild.new(name: name).async.call
      end
    end

    perform_enqueued_jobs do
      Dex::Trace.start(actor: { type: :user, id: 7 }) do
        AsyncTraceParent.new(name: "Ada").call
      end
    end

    assert_match(/\Atr_[1-9A-HJ-NP-Za-km-z]{20}\z/, seen[:trace_id])
    assert_equal "user", seen[:actor][:actor_type]
    assert_equal "7", seen[:actor][:id]
    assert_equal %w[AsyncTraceParent AsyncTraceChild], seen[:classes]
  end

  def test_async_serializes_with_as_json
    model = TestModel.create!(name: "Bob")

    define_operation(:TestSerializeOp) do
      prop :model, _Ref(TestModel)
      prop :due, Date
      def perform = nil
    end

    op = TestSerializeOp.new(model: model, due: Date.new(2025, 6, 15))
    proxy = op.async

    serialized = proxy.send(:serialized_params)

    assert_equal model.id, serialized["model"]
    assert_equal "2025-06-15", serialized["due"]
  end

  def test_async_raises_for_non_serializable_params
    non_serializable_class = Class.new do
      def as_json(*) = self
    end

    define_operation(:TestNonSerOp) do
      prop :data, Object
      def perform = nil
    end

    op = TestNonSerOp.new(data: non_serializable_class.new)

    assert_raises(ArgumentError) { op.async.call }
  end

  def test_async_full_round_trip
    performed = []

    op_class = define_operation(:TestFullRoundTripOp) do
      prop :due, Date
      prop :label, String
    end

    op_class.define_method(:perform) do
      performed << { due: due, label: label }
    end

    op = op_class.new(due: Date.new(2025, 6, 15), label: "test")

    perform_enqueued_jobs do
      op.async.call
    end

    assert_equal [{ due: Date.new(2025, 6, 15), label: "test" }], performed
  end

  def test_direct_call_validates_types
    define_operation(:TestStrictOp) do
      prop :due, Date
      def perform = due
    end

    assert_raises(Literal::TypeError) do
      TestStrictOp.new(due: "2025-06-15").call
    end
  end

  private

  def build_async_operation(parent: Dex::Operation, &block)
    build_operation(parent: parent) do
      prop :name, String

      class_eval(&block) if block

      unless method_defined?(:perform, false)
        def perform
        end
      end
    end
  end
end
