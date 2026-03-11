# frozen_string_literal: true

require "test_helper"

class TestOperationMongoidRecording < Minitest::Test
  include ActiveJob::TestHelper

  def setup
    setup_mongoid_operation_database
  end

  def teardown
    Dex.configure { |c| c.record_class = nil }
    Dex.reset_record_backend!
    clear_enqueued_jobs
    clear_performed_jobs
    super
  end

  def test_backend_auto_detects_mongoid
    backend = Dex::Operation::RecordBackend.for(MongoOperationRecord)

    assert_instance_of Dex::Operation::RecordBackend::MongoidAdapter, backend
  end

  def test_sync_recording_persists_mongoid_document
    with_mongoid_recording do
      op = define_operation(:MongoidSyncRecordingOp) do
        prop :name, String

        def perform
          { greeting: "Hello #{name}" }
        end
      end

      result = op.new(name: "World").call

      assert_equal({ greeting: "Hello World" }, result)

      record = MongoOperationRecord.last
      assert_equal "MongoidSyncRecordingOp", record.name
      assert_equal "completed", record.status
      assert_equal({ "name" => "World" }, normalize_hash(record.params))
      assert_equal({ "greeting" => "Hello World" }, normalize_hash(record.result))
      refute_nil record.performed_at
    end
  end

  def test_recording_respects_params_and_result_options
    with_mongoid_recording do
      op = define_operation(:MongoidSelectiveRecordingOp) do
        record params: false, result: false
        prop :name, String

        def perform
          { greeting: "Hello" }
        end
      end

      op.new(name: "World").call

      record = MongoOperationRecord.last
      assert_nil record.params
      assert_nil record.result
      assert_equal "completed", record.status
    end
  end

  def test_minimal_mongoid_record_class_raises_prescriptive_error
    with_mongoid_recording(record_class: MinimalMongoOperationRecord) do
      op = define_operation(:MongoidMinimalRecordingOp) do
        prop :name, String

        def perform
          { anything: true }
        end
      end

      error = assert_raises(ArgumentError) do
        op.new(name: "World").call
      end

      assert_match(/missing required attributes/, error.message)
      assert_match(/status/, error.message)
      assert_match(/performed_at/, error.message)
    end
  end

  def test_async_record_job_round_trip_updates_status_and_result
    with_mongoid_recording do
      op = define_operation(:MongoidAsyncRecordingOp) do
        prop :name, String

        def perform
          { greeting: "Hello #{name}" }
        end
      end

      op.new(name: "Async").async.call
      record = MongoOperationRecord.last

      Dex::Operation::RecordJob.new.perform(
        class_name: "MongoidAsyncRecordingOp",
        record_id: record.id.to_s
      )

      record.reload
      assert_equal "MongoidAsyncRecordingOp", record.name
      assert_equal "completed", record.status
      assert_equal({ "name" => "Async" }, normalize_hash(record.params))
      assert_equal({ "greeting" => "Hello Async" }, normalize_hash(record.result))
      refute_nil record.performed_at
    end
  end

  def test_async_record_job_marks_error_when_operation_raises_dex_error
    with_mongoid_recording do
      define_operation(:MongoidAsyncFailureOp) do
        prop :name, String
        error :invalid_input

        def perform
          error!(:invalid_input, "Nope")
        end
      end

      MongoidAsyncFailureOp.new(name: "Bad").async.call
      record = MongoOperationRecord.last
      assert_equal "pending", record.status

      assert_raises(Dex::Error) do
        Dex::Operation::RecordJob.new.perform(
          class_name: "MongoidAsyncFailureOp",
          record_id: record.id.to_s
        )
      end

      record.reload
      assert_equal "error", record.status
      assert_equal "invalid_input", record.error_code
      assert_equal "Nope", record.error_message
    end
  end

  def test_recording_sanitizes_untyped_mongoid_document_results
    with_mongoid_recording do
      op = define_operation(:MongoidDocumentResultOp) do
        prop :name, String

        def perform
          MongoTestModel.create!(name: name)
        end
      end

      result = op.new(name: "World").call

      assert_instance_of MongoTestModel, result

      record = MongoOperationRecord.last
      assert_equal "completed", record.status
      assert_respond_to record.result, :[]
      assert_respond_to record.result["_dex_value"], :[]
      assert_equal "World", record.result["_dex_value"]["name"]
    end
  end

  private

  def with_mongoid_recording(record_class: MongoOperationRecord, &block)
    with_recording(record_class: record_class, &block)
  end

  def normalize_hash(value)
    return value unless value.is_a?(Hash)

    value.each_with_object({}) do |(key, nested_value), result|
      result[key.to_s] = normalize_hash(nested_value)
    end
  end
end
