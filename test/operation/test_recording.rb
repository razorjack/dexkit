# frozen_string_literal: true

require "test_helper"

class TestOperationRecording < Minitest::Test
  def setup
    setup_test_database
  end

  def test_recording_disabled_when_not_configured
    op = define_operation(:TestRecordingDisabled) do
      params { attribute :name, Types::String }
      def perform
      end
    end

    op.new(name: "Test").call

    assert_equal 0, OperationRecord.count
  end

  def test_recording_enabled_when_configured
    with_recording do
      op = define_operation(:TestRecordingEnabled) do
        params { attribute :name, Types::String }
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
        params { attribute :name, Types::String }
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
        params { attribute :name, Types::String }
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
        params { attribute :name, Types::String }
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
        params { attribute :name, Types::String }
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
        params { attribute :name, Types::String }
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
        params { attribute :name, Types::String }
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
        params { attribute :name, Types::String }
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
        params { attribute :name, Types::String }
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

  # Response recording tests

  def test_records_response_hash
    with_recording do
      op = define_operation(:TestRecordsResponseHash) do
        params { attribute :name, Types::String }
        def perform
          { greeting: "Hello #{name}" }
        end
      end

      op.new(name: "World").call

      assert_equal({ "greeting" => "Hello World" }, OperationRecord.last.response)
    end
  end

  def test_records_response_with_success_type
    with_recording do
      op = define_operation(:TestRecordsResponseWithSuccessType) do
        params { attribute :name, Types::String }
        success Types::String

        define_method(:perform) { "Hello #{name}" }
      end

      op.new(name: "World").call

      assert_equal "Hello World", OperationRecord.last.response
    end
  end

  def test_records_nil_response
    with_recording do
      op = define_operation(:TestRecordsNilResponse) do
        params { attribute :name, Types::String }
        def perform
          nil
        end
      end

      op.new(name: "Test").call

      assert_nil OperationRecord.last.response
    end
  end

  def test_records_primitive_response_wrapped
    with_recording do
      op = define_operation(:TestRecordsPrimitiveResponse) do
        params { attribute :name, Types::String }
        def perform
          42
        end
      end

      op.new(name: "Test").call

      assert_equal({ "value" => 42 }, OperationRecord.last.response)
    end
  end

  def test_missing_response_column_still_works
    with_recording(record_class: MinimalOperationRecord) do
      op = define_operation(:TestMissingResponseColumn) do
        params { attribute :name, Types::String }
        def perform
          { result: "success" }
        end
      end

      op.new(name: "Test").call

      assert_equal 1, MinimalOperationRecord.count
      assert_equal "TestMissingResponseColumn", MinimalOperationRecord.last.name
    end
  end

  def test_error_does_not_record
    with_recording do
      op = define_operation(:TestErrorDoesNotRecord) do
        params { attribute :name, Types::String }
        def perform
          error!(:test_error, "Test error message")
        end
      end

      assert_raises(Dex::Error) do
        op.new(name: "Test").call
      end

      assert_equal 0, OperationRecord.count
    end
  end

  def test_record_response_false_skips_response
    with_recording do
      op = define_operation(:TestRecordResponseFalse) do
        record response: false
        params { attribute :name, Types::String }
        def perform
          { greeting: "Hello" }
        end
      end

      op.new(name: "Test").call

      record = OperationRecord.last
      assert_equal({ "name" => "Test" }, record.params)
      assert_nil record.response
    end
  end

  def test_record_params_false_skips_params
    with_recording do
      op = define_operation(:TestRecordParamsFalse) do
        record params: false
        params { attribute :name, Types::String }
        def perform
          { greeting: "Hello" }
        end
      end

      op.new(name: "Test").call

      record = OperationRecord.last
      assert_nil record.params
      assert_equal({ "greeting" => "Hello" }, record.response)
    end
  end

  def test_record_defaults_include_both
    with_recording do
      op = define_operation(:TestRecordDefaults) do
        record true
        params { attribute :name, Types::String }
        def perform
          { greeting: "Hello" }
        end
      end

      op.new(name: "Test").call

      record = OperationRecord.last
      assert_equal({ "name" => "Test" }, record.params)
      assert_equal({ "greeting" => "Hello" }, record.response)
    end
  end
end
