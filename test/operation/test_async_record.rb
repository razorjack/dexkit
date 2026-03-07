# frozen_string_literal: true

require "test_helper"

class TestOperationAsyncRecord < Minitest::Test
  include ActiveJob::TestHelper

  def setup
    setup_test_database
  end

  # --- Strategy detection ---

  def test_uses_record_job_when_recording_enabled
    with_recording do
      op_class = define_operation(:TestRecordJobStrategy) do
        prop :name, String
        def perform = nil
      end

      assert_enqueued_with(job: Dex::Operation::RecordJob) do
        op_class.new(name: "Test").async.call
      end
    end
  end

  def test_falls_back_to_direct_job_when_no_recording
    op_class = define_operation(:TestDirectJobFallback) do
      prop :name, String
      def perform = nil
    end

    assert_enqueued_with(job: Dex::Operation::DirectJob) do
      op_class.new(name: "Test").async.call
    end
  end

  def test_falls_back_to_direct_job_when_record_false
    with_recording do
      op_class = define_operation(:TestRecordFalseDirectJob) do
        record false
        prop :name, String
        def perform = nil
      end

      assert_enqueued_with(job: Dex::Operation::DirectJob) do
        op_class.new(name: "Test").async.call
      end
    end
  end

  def test_falls_back_to_direct_job_when_record_params_false
    with_recording do
      op_class = define_operation(:TestParamsFalseDirectJob) do
        record params: false
        prop :name, String
        def perform = nil
      end

      assert_enqueued_with(job: Dex::Operation::DirectJob) do
        op_class.new(name: "Test").async.call
      end
    end
  end

  def test_falls_back_to_direct_job_for_anonymous_class
    with_recording do
      op_class = build_operation do
        prop :name, String
        def perform = nil
      end

      assert_enqueued_with(job: Dex::Operation::DirectJob) do
        op_class.new(name: "Test").async.call
      end
    end
  end

  # --- Pending record creation ---

  def test_creates_pending_record_at_enqueue
    with_recording do
      op_class = define_operation(:TestPendingRecord) do
        prop :name, String
        def perform = nil
      end

      op_class.new(name: "Test").async.call

      record = OperationRecord.last
      assert_equal "pending", record.status
      assert_equal "TestPendingRecord", record.name
      assert_equal({ "name" => "Test" }, record.params)
    end
  end

  # --- RecordJob round-trip ---

  def test_record_job_basic_round_trip
    with_recording do
      op_class = define_operation(:TestRecordRoundTrip) do
        prop :name, String
        def perform = { greeting: "Hello #{name}" }
      end

      op_class.new(name: "World").async.call
      record = OperationRecord.last
      assert_equal "pending", record.status

      Dex::Operation::RecordJob.new.perform(
        class_name: "TestRecordRoundTrip",
        record_id: record.id
      )

      record.reload
      assert_equal "completed", record.status
      assert_equal({ "greeting" => "Hello World" }, record.result)
      refute_nil record.performed_at
    end
  end

  def test_record_job_typed_params_round_trip
    with_recording do
      op_class = define_operation(:TestRecordTypedParams) do
        prop :due, Date
        prop :status, Symbol
        def perform = { due: due, status: status }
      end

      op_class.new(due: Date.new(2025, 6, 15), status: :active).async.call
      record = OperationRecord.last

      result = Dex::Operation::RecordJob.new.perform(
        class_name: "TestRecordTypedParams",
        record_id: record.id
      )

      assert_equal Date.new(2025, 6, 15), result[:due]
      assert_equal :active, result[:status]
    end
  end

  def test_record_job_with_record_type
    with_recording do
      model = TestModel.create!(name: "Alice")

      op_class = define_operation(:TestRecordJobRecordType) do
        prop :model, _Ref(TestModel)
        def perform = model
      end

      op_class.new(model: model).async.call
      record = OperationRecord.last

      result = Dex::Operation::RecordJob.new.perform(
        class_name: "TestRecordJobRecordType",
        record_id: record.id
      )

      assert_equal model, result
    end
  end

  def test_record_job_full_active_job_round_trip
    with_recording do
      op_class = define_operation(:TestRecordFullRoundTrip) do
        prop :name, String
        def perform = { name: name }
      end

      perform_enqueued_jobs do
        op_class.new(name: "FullTrip").async.call
      end

      record = OperationRecord.last
      assert_equal "completed", record.status
      assert_equal({ "name" => "FullTrip" }, record.result)
    end
  end

  # --- Status transitions ---

  def test_status_transitions_success
    with_recording do
      define_operation(:TestStatusSuccess) do
        prop :name, String
        def perform = nil
      end

      TestStatusSuccess.new(name: "Test").async.call

      record = OperationRecord.last
      assert_equal "pending", record.status

      Dex::Operation::RecordJob.new.perform(
        class_name: "TestStatusSuccess",
        record_id: record.id
      )

      record.reload
      assert_equal "completed", record.status
    end
  end

  def test_status_transitions_dex_error
    with_recording do
      define_operation(:TestStatusDexError) do
        prop :name, String
        def perform = error!(:bad_input, "Invalid")
      end

      TestStatusDexError.new(name: "Test").async.call
      record = OperationRecord.last

      assert_raises(Dex::Error) do
        Dex::Operation::RecordJob.new.perform(
          class_name: "TestStatusDexError",
          record_id: record.id
        )
      end

      record.reload
      assert_equal "error", record.status
      assert_equal "bad_input", record.error_code
      assert_equal "Invalid", record.error_message
    end
  end

  def test_status_transitions_unhandled_exception
    with_recording do
      define_operation(:TestStatusException) do
        prop :name, String
        def perform = raise "boom"
      end

      TestStatusException.new(name: "Test").async.call
      record = OperationRecord.last

      assert_raises(RuntimeError) do
        Dex::Operation::RecordJob.new.perform(
          class_name: "TestStatusException",
          record_id: record.id
        )
      end

      record.reload
      assert_equal "failed", record.status
      assert_equal "RuntimeError", record.error_code
      assert_equal "boom", record.error_message
    end
  end

  # --- Edge cases ---

  def test_record_deleted_before_job_runs
    with_recording do
      define_operation(:TestRecordDeleted) do
        prop :name, String
        def perform = nil
      end

      TestRecordDeleted.new(name: "Test").async.call
      record = OperationRecord.last
      deleted_id = record.id
      record.destroy!

      assert_raises(ActiveRecord::RecordNotFound) do
        Dex::Operation::RecordJob.new.perform(
          class_name: "TestRecordDeleted",
          record_id: deleted_id
        )
      end
    end
  end

  def test_record_result_false_skips_result_on_completed
    with_recording do
      define_operation(:TestRecordResultFalseAsync) do
        record result: false
        prop :name, String
        def perform = { greeting: "Hello" }
      end

      TestRecordResultFalseAsync.new(name: "Test").async.call
      record = OperationRecord.last

      Dex::Operation::RecordJob.new.perform(
        class_name: "TestRecordResultFalseAsync",
        record_id: record.id
      )

      record.reload
      assert_equal "completed", record.status
      assert_nil record.result
    end
  end

  def test_minimal_table_without_status_column
    with_recording(record_class: MinimalOperationRecord) do
      define_operation(:TestMinimalTableAsync) do
        prop :name, String
        def perform = nil
      end

      # Should not raise even though MinimalOperationRecord lacks status/error columns
      TestMinimalTableAsync.new(name: "Test").async.call
      assert_equal 1, MinimalOperationRecord.count
    end
  end

  # --- Sync path still sets status ---

  def test_sync_call_sets_completed_status
    with_recording do
      define_operation(:TestSyncCompletedStatus) do
        prop :name, String
        def perform = nil
      end

      TestSyncCompletedStatus.new(name: "Test").call

      record = OperationRecord.last
      assert_equal "completed", record.status
    end
  end

  # --- Backward compatibility ---

  def test_job_alias_works
    assert_equal Dex::Operation::DirectJob, Dex::Operation::Job
  end

  def test_async_options_work_with_record_job
    with_recording do
      op_class = define_operation(:TestRecordJobOptions) do
        prop :name, String
        def perform = nil
      end

      assert_enqueued_with(job: Dex::Operation::RecordJob, queue: "low") do
        op_class.new(name: "Test").async(queue: "low").call
      end
    end
  end

  def test_pre_call_failure_marks_record_failed
    with_recording do
      op_class = define_operation(:TestPreCallFailure) do
        prop :model, _Ref(TestModel)
        def perform = model
      end

      model = TestModel.create!(name: "Temp")
      op_class.new(model: model).async.call
      record = OperationRecord.last
      model.destroy!

      assert_raises(ActiveRecord::RecordNotFound) do
        Dex::Operation::RecordJob.new.perform(
          class_name: "TestPreCallFailure",
          record_id: record.id
        )
      end

      record.reload
      assert_equal "failed", record.status
      assert_equal "ActiveRecord::RecordNotFound", record.error_code
      refute_nil record.error_message
      refute_nil record.performed_at
    end
  end
end
