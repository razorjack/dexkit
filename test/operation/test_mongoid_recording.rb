# frozen_string_literal: true

require "test_helper"

class TestOperationMongoidRecording < Minitest::Test
  include ActiveJob::TestHelper

  def setup
    setup_mongoid_operation_database
    Dex.configure { |c| c.transaction_adapter = :mongoid }
  end

  def teardown
    Dex.configure { |c| c.record_class = nil }
    Dex.configure { |c| c.transaction_adapter = nil }
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
      assert_equal "done", record.status
      assert_equal({ "name" => "World" }, normalize_hash(record.params))
      assert_equal({ "greeting" => "Hello World" }, normalize_hash(record.response))
      refute_nil record.performed_at
    end
  end

  def test_recording_respects_params_and_response_options
    with_mongoid_recording do
      op = define_operation(:MongoidSelectiveRecordingOp) do
        record params: false, response: false
        prop :name, String

        def perform
          { greeting: "Hello" }
        end
      end

      op.new(name: "World").call

      record = MongoOperationRecord.last
      assert_nil record.params
      assert_nil record.response
      assert_equal "done", record.status
    end
  end

  def test_minimal_mongoid_record_class_ignores_unknown_attributes
    with_mongoid_recording(record_class: MinimalMongoOperationRecord) do
      op = define_operation(:MongoidMinimalRecordingOp) do
        prop :name, String

        def perform
          { anything: true }
        end
      end

      op.new(name: "World").call

      assert_equal 1, MinimalMongoOperationRecord.count

      record = MinimalMongoOperationRecord.last
      assert_equal "MongoidMinimalRecordingOp", record.name
      refute_includes record.attributes.keys, "params"
      refute_includes record.attributes.keys, "response"
    end
  end

  def test_async_record_job_round_trip_updates_status_and_response
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
      assert_equal "done", record.status
      assert_equal({ "name" => "Async" }, normalize_hash(record.params))
      assert_equal({ "greeting" => "Hello Async" }, normalize_hash(record.response))
      refute_nil record.performed_at
    end
  end

  def test_async_record_job_marks_failed_when_operation_raises_dex_error
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
      assert_equal "failed", record.status
      assert_equal "invalid_input", record.error
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
