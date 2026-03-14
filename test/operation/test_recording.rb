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

  def test_records_execution_id_trace_and_actor
    with_recording do
      op = define_operation(:TestTraceRecord) do
        prop :name, String
        def perform
        end
      end

      Dex::Trace.start(actor: { type: :user, id: 123 }) do
        op.new(name: "TestValue").call
      end

      record = OperationRecord.last
      trace = record.trace.map { |frame| frame.transform_keys(&:to_s) }

      assert_match(/\Aop_[1-9A-HJ-NP-Za-km-z]{20}\z/, record.id)
      assert_match(/\Atr_[1-9A-HJ-NP-Za-km-z]{20}\z/, record.trace_id)
      assert_equal "user", record.actor_type
      assert_equal "123", record.actor_id
      assert_equal "actor", trace.first["type"]
      assert_equal "TestTraceRecord", trace.last["class"]
      assert_equal record.id, trace.last["id"]
    end
  end

  def test_record_disable_mechanisms
    with_recording do
      # record false
      op1 = define_operation(:TestRecordFalseOp) do
        record false
        prop :name, String
        def perform
        end
      end
      op1.new(name: "Test").call
      assert_equal 0, OperationRecord.count

      # set :record, enabled: false
      op2 = define_operation(:TestSetRecordFalseOp) do
        set :record, enabled: false
        prop :name, String
        def perform
        end
      end
      op2.new(name: "Test").call
      assert_equal 0, OperationRecord.count
    end
  end

  def test_missing_record_fields_raise_prescriptive_error
    with_recording(record_class: MinimalOperationRecord) do
      op = define_operation(:TestMinimalFieldsOp) do
        prop :name, String
        def perform
        end
      end

      error = assert_raises(ArgumentError) do
        op.new(name: "Test").call
      end

      assert_match(/missing required attributes/, error.message)
      assert_match(/status/, error.message)
      assert_match(/performed_at/, error.message)
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

  def test_record_inheritance
    with_recording do
      # record false inherits to children
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

      # Child can re-enable with record true
      child2 = define_operation(:TestChildReenabled, parent: parent) do
        record true
        prop :name, String
        def perform
        end
      end

      child2.new(name: "Test").call
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

  def test_records_various_result_types
    with_recording do
      # Hash result
      op1 = define_operation(:TestRecordsResultHash) do
        prop :name, String
        def perform
          { greeting: "Hello #{name}" }
        end
      end
      op1.new(name: "World").call
      assert_equal({ "greeting" => "Hello World" }, OperationRecord.last.result)

      # Nil result
      op2 = define_operation(:TestRecordsNilResult) do
        prop :name, String
        def perform
          nil
        end
      end
      op2.new(name: "Test").call
      assert_nil OperationRecord.where(name: "TestRecordsNilResult").last.result

      # Primitive result (wrapped)
      op3 = define_operation(:TestRecordsPrimitiveResult) do
        prop :name, String
        def perform
          42
        end
      end
      op3.new(name: "Test").call
      assert_equal({ "_dex_value" => 42 }, OperationRecord.where(name: "TestRecordsPrimitiveResult").last.result)
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

  def test_missing_result_column_raises_prescriptive_error
    with_recording(record_class: MinimalOperationRecord) do
      op = define_operation(:TestMissingResultColumn) do
        prop :name, String
        def perform
          { result: "success" }
        end
      end

      error = assert_raises(ArgumentError) do
        op.new(name: "Test").call
      end

      assert_match(/missing required attributes/, error.message)
      assert_match(/result/, error.message)
    end
  end

  def test_records_status_transitions
    with_recording do
      # Success records as completed with performed_at
      op1 = define_operation(:TestCompletedStatus) do
        prop :name, String
        def perform
        end
      end
      op1.new(name: "Test").call
      assert_equal "completed", OperationRecord.last.status
      refute_nil OperationRecord.last.performed_at

      # Business error records with error status
      op2 = define_operation(:TestErrorRecords) do
        prop :name, String
        def perform
          error!(:test_error, "Test error message")
        end
      end
      assert_raises(Dex::Error) { op2.new(name: "Test").call }
      record2 = OperationRecord.where(name: "TestErrorRecords").last
      assert_equal "error", record2.status
      assert_equal "test_error", record2.error_code
      assert_equal "Test error message", record2.error_message
      refute_nil record2.performed_at

      # Exception records with failed status
      op3 = define_operation(:TestExceptionRecords) do
        prop :name, String
        def perform
          raise "boom"
        end
      end
      assert_raises(RuntimeError) { op3.new(name: "Test").call }
      record3 = OperationRecord.where(name: "TestExceptionRecords").last
      assert_equal "failed", record3.status
      assert_equal "RuntimeError", record3.error_code
      assert_equal "boom", record3.error_message
      refute_nil record3.performed_at
    end
  end

  def test_records_error_details_shapes
    with_recording do
      # Hash details
      op1 = define_operation(:TestErrorRecordsDetails) do
        prop :name, String
        def perform
          error!(:validation_failed, "Invalid input", details: { field: "name" })
        end
      end
      assert_raises(Dex::Error) { op1.new(name: "Test").call }
      record1 = OperationRecord.where(name: "TestErrorRecordsDetails").last
      assert_equal({ "field" => "name" }, record1.error_details)

      # Array details
      op2 = define_operation(:TestErrorDetailsArray) do
        prop :name, String
        def perform
          error!(:bad, "bad input", details: [1, "two", nil, false])
        end
      end
      assert_raises(Dex::Error) { op2.new(name: "Test").call }
      record2 = OperationRecord.where(name: "TestErrorDetailsArray").last
      assert_equal [1, "two", nil, false], record2.error_details

      # Nested hash with arrays
      op3 = define_operation(:TestErrorDetailsNested) do
        prop :name, String
        def perform
          error!(:bad, "bad", details: { ids: [1, 2, 3], nested: { ok: true } })
        end
      end
      assert_raises(Dex::Error) { op3.new(name: "Test").call }
      record3 = OperationRecord.where(name: "TestErrorDetailsNested").last
      assert_equal({ "ids" => [1, 2, 3], "nested" => { "ok" => true } }, record3.error_details)
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

  def test_nested_operation_record_contains_full_trace_chain
    with_recording do
      inner = define_operation(:TraceInnerRecordedOp) do
        prop :name, String
        def perform
          nil
        end
      end

      outer = define_operation(:TraceOuterRecordedOp) do
        prop :name, String
        define_method(:perform) { inner.call(name: name) }
      end

      outer.new(name: "Test").call

      inner_record = OperationRecord.where(name: "TraceInnerRecordedOp").last
      trace_classes = inner_record.trace.map { |frame| frame["class"] || frame[:class] }.compact

      assert_equal [inner_record.trace_id], OperationRecord.all.map(&:trace_id).uniq
      assert_equal %w[TraceOuterRecordedOp TraceInnerRecordedOp], trace_classes
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
end
