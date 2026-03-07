# frozen_string_literal: true

require "test_helper"

class TestOperationRecording < Minitest::Test
  def setup
    setup_test_database
  end

  def test_recording_disabled_when_not_configured
    op = define_operation(:TestRecordingDisabled) do
      prop :name, String
      def perform
      end
    end

    op.new(name: "Test").call

    assert_equal 0, OperationRecord.count
  end

  def test_recording_enabled_when_configured
    with_recording do
      op = define_operation(:TestRecordingEnabled) do
        prop :name, String
        def perform
        end
      end

      op.new(name: "Test").call

      assert_equal 1, OperationRecord.count
    end
  end

  def test_records_operation_name
    with_recording do
      op = define_operation(:NamedOperation) do
        prop :name, String
        def perform
        end
      end

      op.new(name: "Test").call

      assert_equal "NamedOperation", OperationRecord.last.name
    end
  end

  def test_records_params_as_json
    with_recording do
      op = define_operation(:TestRecordsParams) do
        prop :name, String
        def perform
        end
      end

      op.new(name: "TestValue").call

      assert_equal({ "name" => "TestValue" }, OperationRecord.last.params)
    end
  end

  def test_record_false_disables_for_class
    with_recording do
      op = define_operation(:TestRecordFalseOp) do
        record false
        prop :name, String
        def perform
        end
      end

      op.new(name: "Test").call

      assert_equal 0, OperationRecord.count
    end
  end

  def test_set_record_enabled_false_disables
    with_recording do
      op = define_operation(:TestSetRecordFalseOp) do
        set :record, enabled: false
        prop :name, String
        def perform
        end
      end

      op.new(name: "Test").call

      assert_equal 0, OperationRecord.count
    end
  end

  def test_missing_params_field_still_works
    with_recording(record_class: MinimalOperationRecord) do
      op = define_operation(:TestMinimalFieldsOp) do
        prop :name, String
        def perform
        end
      end

      op.new(name: "Test").call

      assert_equal 1, MinimalOperationRecord.count
      assert_equal "TestMinimalFieldsOp", MinimalOperationRecord.last.name
    end
  end

  def test_database_error_does_not_break_operation
    with_recording do
      result = []
      op = define_operation(:TestDbErrorOp) do
        prop :name, String
        define_method(:perform) { result << :executed }
      end

      # Simulate database error by stubbing create!
      OperationRecord.stub :create!, ->(*) { raise ActiveRecord::StatementInvalid, "DB Error" } do
        op.new(name: "Test").call
      end

      assert_equal [:executed], result
    end
  end

  def test_record_false_inherits_to_children
    with_recording do
      parent = define_operation(:TestParentNoRecord) do
        record false
      end

      child = define_operation(:TestChildInheritsNoRecord, parent: parent) do
        prop :name, String
        def perform
        end
      end

      child.new(name: "Test").call

      assert_equal 0, OperationRecord.count
    end
  end

  def test_child_can_reenable_with_record_true
    with_recording do
      parent = define_operation(:TestParentNoRecord2) do
        record false
      end

      child = define_operation(:TestChildReenabled, parent: parent) do
        record true
        prop :name, String
        def perform
        end
      end

      child.new(name: "Test").call

      assert_equal 1, OperationRecord.count
    end
  end

  def test_backend_auto_detects_active_record
    backend = Dex::Operation::RecordBackend.for(OperationRecord)

    assert_instance_of Dex::Operation::RecordBackend::ActiveRecordAdapter, backend
  end

  def test_backend_returns_nil_when_no_record_class
    backend = Dex::Operation::RecordBackend.for(nil)

    assert_nil backend
  end

  # Result recording tests

  def test_records_result_hash
    with_recording do
      op = define_operation(:TestRecordsResultHash) do
        prop :name, String
        def perform
          { greeting: "Hello #{name}" }
        end
      end

      op.new(name: "World").call

      assert_equal({ "greeting" => "Hello World" }, OperationRecord.last.result)
    end
  end

  def test_records_result_with_success_type
    with_recording do
      op = define_operation(:TestRecordsResultWithSuccessType) do
        prop :name, String
        success String

        define_method(:perform) { "Hello #{name}" }
      end

      op.new(name: "World").call

      assert_equal "Hello World", OperationRecord.last.result
    end
  end

  def test_records_nil_result
    with_recording do
      op = define_operation(:TestRecordsNilResult) do
        prop :name, String
        def perform
          nil
        end
      end

      op.new(name: "Test").call

      assert_nil OperationRecord.last.result
    end
  end

  def test_records_primitive_result_wrapped
    with_recording do
      op = define_operation(:TestRecordsPrimitiveResult) do
        prop :name, String
        def perform
          42
        end
      end

      op.new(name: "Test").call

      assert_equal({ "_dex_value" => 42 }, OperationRecord.last.result)
    end
  end

  def test_missing_result_column_still_works
    with_recording(record_class: MinimalOperationRecord) do
      op = define_operation(:TestMissingResultColumn) do
        prop :name, String
        def perform
          { result: "success" }
        end
      end

      op.new(name: "Test").call

      assert_equal 1, MinimalOperationRecord.count
      assert_equal "TestMissingResultColumn", MinimalOperationRecord.last.name
    end
  end

  def test_business_error_records_with_error_status
    with_recording do
      op = define_operation(:TestErrorRecords) do
        prop :name, String
        def perform
          error!(:test_error, "Test error message")
        end
      end

      assert_raises(Dex::Error) do
        op.new(name: "Test").call
      end

      assert_equal 1, OperationRecord.count
      record = OperationRecord.last
      assert_equal "error", record.status
      assert_equal "test_error", record.error_code
      assert_equal "Test error message", record.error_message
      refute_nil record.performed_at
    end
  end

  def test_business_error_records_details
    with_recording do
      op = define_operation(:TestErrorRecordsDetails) do
        prop :name, String
        def perform
          error!(:validation_failed, "Invalid input", details: { field: "name" })
        end
      end

      assert_raises(Dex::Error) do
        op.new(name: "Test").call
      end

      record = OperationRecord.last
      assert_equal "error", record.status
      assert_equal "validation_failed", record.error_code
      assert_equal({ "field" => "name" }, record.error_details)
    end
  end

  def test_exception_records_with_failed_status
    with_recording do
      op = define_operation(:TestExceptionRecords) do
        prop :name, String
        def perform
          raise "boom"
        end
      end

      assert_raises(RuntimeError) do
        op.new(name: "Test").call
      end

      assert_equal 1, OperationRecord.count
      record = OperationRecord.last
      assert_equal "failed", record.status
      assert_equal "RuntimeError", record.error_code
      assert_equal "boom", record.error_message
      refute_nil record.performed_at
    end
  end

  def test_success_bang_records
    with_recording do
      op = define_operation(:TestSuccessBangRecords) do
        prop :name, String
        def perform
          success!("early result")
        end
      end

      result = op.new(name: "Test").call

      assert_equal "early result", result
      assert_equal 1, OperationRecord.count
      assert_equal({ "_dex_value" => "early result" }, OperationRecord.last.result)
    end
  end

  def test_record_result_false_skips_result
    with_recording do
      op = define_operation(:TestRecordResultFalse) do
        record result: false
        prop :name, String
        def perform
          { greeting: "Hello" }
        end
      end

      op.new(name: "Test").call

      record = OperationRecord.last
      assert_equal({ "name" => "Test" }, record.params)
      assert_nil record.result
    end
  end

  def test_record_params_false_skips_params
    with_recording do
      op = define_operation(:TestRecordParamsFalse) do
        record params: false
        prop :name, String
        def perform
          { greeting: "Hello" }
        end
      end

      op.new(name: "Test").call

      record = OperationRecord.last
      assert_nil record.params
      assert_equal({ "greeting" => "Hello" }, record.result)
    end
  end

  def test_record_defaults_include_both
    with_recording do
      op = define_operation(:TestRecordDefaults) do
        record true
        prop :name, String
        def perform
          { greeting: "Hello" }
        end
      end

      op.new(name: "Test").call

      record = OperationRecord.last
      assert_equal({ "name" => "Test" }, record.params)
      assert_equal({ "greeting" => "Hello" }, record.result)
    end
  end

  def test_completed_status_on_success
    with_recording do
      op = define_operation(:TestCompletedStatus) do
        prop :name, String
        def perform
        end
      end

      op.new(name: "Test").call

      assert_equal "completed", OperationRecord.last.status
    end
  end

  def test_performed_at_set_on_success
    with_recording do
      op = define_operation(:TestPerformedAtSuccess) do
        prop :name, String
        def perform
        end
      end

      op.new(name: "Test").call

      refute_nil OperationRecord.last.performed_at
    end
  end

  def test_raised_dex_error_records_as_error_not_failed
    with_recording do
      op = define_operation(:TestRaisedDexError) do
        prop :name, String
        def perform
          raise Dex::Error.new(:explicit_code, "explicit message", details: { key: "val" })
        end
      end

      assert_raises(Dex::Error) do
        op.new(name: "Test").call
      end

      assert_equal 1, OperationRecord.count
      record = OperationRecord.last
      assert_equal "error", record.status
      assert_equal "explicit_code", record.error_code
      assert_equal "explicit message", record.error_message
      assert_equal({ "key" => "val" }, record.error_details)
    end
  end

  def test_nested_operation_dex_error_records_outer_as_error
    with_recording do
      inner = define_operation(:TestInnerOp) do
        prop :name, String
        def perform
          error!(:inner_failure, "from inner")
        end
      end

      outer = define_operation(:TestOuterOp) do
        transaction false
        prop :name, String
        define_method(:perform) { inner.call(name: name) }
      end

      assert_raises(Dex::Error) do
        outer.new(name: "Test").call
      end

      # Inner records via halt path, outer records via rescue path (Dex::Error preserves metadata)
      assert_equal 2, OperationRecord.count
      outer_record = OperationRecord.where(name: "TestOuterOp").last
      assert_equal "error", outer_record.status
      assert_equal "inner_failure", outer_record.error_code
      assert_equal "from inner", outer_record.error_message
    end
  end

  def test_rescue_from_error_details_serialized_cleanly
    with_recording do
      op = define_operation(:TestRescueFromRecording) do
        rescue_from RuntimeError, as: :runtime_failure
        prop :name, String
        def perform
          raise "kaboom"
        end
      end

      assert_raises(Dex::Error) do
        op.new(name: "Test").call
      end

      record = OperationRecord.last
      assert_equal "error", record.status
      assert_equal "runtime_failure", record.error_code
      # original exception is stringified for JSON serialization
      assert_equal "RuntimeError: kaboom", record.error_details["original"]
    end
  end

  def test_error_without_message_records_code_as_message
    with_recording do
      op = define_operation(:TestErrorNoMessage) do
        prop :name, String
        def perform
          error!(:not_found)
        end
      end

      assert_raises(Dex::Error) do
        op.new(name: "Test").call
      end

      record = OperationRecord.last
      assert_equal "error", record.status
      assert_equal "not_found", record.error_code
      assert_equal "not_found", record.error_message
    end
  end

  def test_error_details_array_preserved
    with_recording do
      op = define_operation(:TestErrorDetailsArray) do
        prop :name, String
        def perform
          error!(:bad, "bad input", details: [1, "two", nil, false])
        end
      end

      assert_raises(Dex::Error) do
        op.new(name: "Test").call
      end

      record = OperationRecord.last
      assert_equal [1, "two", nil, false], record.error_details
    end
  end

  def test_error_details_nested_hash_with_arrays
    with_recording do
      op = define_operation(:TestErrorDetailsNested) do
        prop :name, String
        def perform
          error!(:bad, "bad", details: { ids: [1, 2, 3], nested: { ok: true } })
        end
      end

      assert_raises(Dex::Error) do
        op.new(name: "Test").call
      end

      record = OperationRecord.last
      assert_equal({ "ids" => [1, 2, 3], "nested" => { "ok" => true } }, record.error_details)
    end
  end
end
