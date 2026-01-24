# frozen_string_literal: true

require "test_helper"

class TestOperationRecording < Minitest::Test
  def setup
    setup_database
    Dex.reset_record_backend!
  end

  def teardown
    Dex.configure { |c| c.record_class = nil }
    Dex.reset_record_backend!
  end

  def test_recording_disabled_when_not_configured
    op_class = build_named_operation(:TestRecordingDisabled)
    op_class.new(name: "Test").perform

    assert_equal 0, OperationRecord.count
  ensure
    Object.send(:remove_const, :TestRecordingDisabled) if defined?(TestRecordingDisabled)
  end

  def test_recording_enabled_when_configured
    Dex.configure { |c| c.record_class = OperationRecord }

    op_class = build_named_operation(:TestRecordingEnabled)
    op_class.new(name: "Test").perform

    assert_equal 1, OperationRecord.count
  ensure
    Object.send(:remove_const, :TestRecordingEnabled) if defined?(TestRecordingEnabled)
  end

  def test_records_operation_name
    Dex.configure { |c| c.record_class = OperationRecord }

    op_class = Class.new(Dex::Operation) do
      params { attribute :name, Types::String }
      def perform; end
    end
    Object.const_set(:NamedOperation, op_class)

    NamedOperation.new(name: "Test").perform

    assert_equal "NamedOperation", OperationRecord.last.name
  ensure
    Object.send(:remove_const, :NamedOperation)
  end

  def test_records_params_as_json
    Dex.configure { |c| c.record_class = OperationRecord }

    op_class = build_named_operation(:TestRecordsParams)
    op_class.new(name: "TestValue").perform

    assert_equal({ "name" => "TestValue" }, OperationRecord.last.params)
  ensure
    Object.send(:remove_const, :TestRecordsParams) if defined?(TestRecordsParams)
  end

  def test_record_false_disables_for_class
    Dex.configure { |c| c.record_class = OperationRecord }

    op_class = Class.new(Dex::Operation) do
      record false
      params { attribute :name, Types::String }
      def perform; end
    end
    Object.const_set(:TestRecordFalseOp, op_class)

    TestRecordFalseOp.new(name: "Test").perform

    assert_equal 0, OperationRecord.count
  ensure
    Object.send(:remove_const, :TestRecordFalseOp) if defined?(TestRecordFalseOp)
  end

  def test_set_record_enabled_false_disables
    Dex.configure { |c| c.record_class = OperationRecord }

    op_class = Class.new(Dex::Operation) do
      set :record, enabled: false
      params { attribute :name, Types::String }
      def perform; end
    end
    Object.const_set(:TestSetRecordFalseOp, op_class)

    TestSetRecordFalseOp.new(name: "Test").perform

    assert_equal 0, OperationRecord.count
  ensure
    Object.send(:remove_const, :TestSetRecordFalseOp) if defined?(TestSetRecordFalseOp)
  end

  def test_missing_params_field_still_works
    Dex.configure { |c| c.record_class = MinimalOperationRecord }

    op_class = build_named_operation(:TestMinimalFieldsOp)
    op_class.new(name: "Test").perform

    assert_equal 1, MinimalOperationRecord.count
    assert_equal "TestMinimalFieldsOp", MinimalOperationRecord.last.name
  ensure
    Object.send(:remove_const, :TestMinimalFieldsOp) if defined?(TestMinimalFieldsOp)
  end

  def test_database_error_does_not_break_operation
    Dex.configure { |c| c.record_class = OperationRecord }

    result = []
    op_class = Class.new(Dex::Operation) do
      params { attribute :name, Types::String }
      define_method(:perform) { result << :executed }
    end
    Object.const_set(:TestDbErrorOp, op_class)

    # Simulate database error by stubbing create!
    OperationRecord.stub :create!, ->(*) { raise ActiveRecord::StatementInvalid, "DB Error" } do
      TestDbErrorOp.new(name: "Test").perform
    end

    assert_equal [:executed], result
  ensure
    Object.send(:remove_const, :TestDbErrorOp) if defined?(TestDbErrorOp)
  end

  def test_record_false_inherits_to_children
    Dex.configure { |c| c.record_class = OperationRecord }

    parent = Class.new(Dex::Operation) do
      record false
    end
    Object.const_set(:TestParentNoRecord, parent)

    child = Class.new(parent) do
      params { attribute :name, Types::String }
      def perform; end
    end
    Object.const_set(:TestChildInheritsNoRecord, child)

    TestChildInheritsNoRecord.new(name: "Test").perform

    assert_equal 0, OperationRecord.count
  ensure
    Object.send(:remove_const, :TestChildInheritsNoRecord) if defined?(TestChildInheritsNoRecord)
    Object.send(:remove_const, :TestParentNoRecord) if defined?(TestParentNoRecord)
  end

  def test_child_can_reenable_with_record_true
    Dex.configure { |c| c.record_class = OperationRecord }

    parent = Class.new(Dex::Operation) do
      record false
    end
    Object.const_set(:TestParentNoRecord2, parent)

    child = Class.new(parent) do
      record true
      params { attribute :name, Types::String }
      def perform; end
    end
    Object.const_set(:TestChildReenabled, child)

    TestChildReenabled.new(name: "Test").perform

    assert_equal 1, OperationRecord.count
  ensure
    Object.send(:remove_const, :TestChildReenabled) if defined?(TestChildReenabled)
    Object.send(:remove_const, :TestParentNoRecord2) if defined?(TestParentNoRecord2)
  end

  def test_backend_auto_detects_active_record
    backend = Dex::Operation::RecordBackend.for(OperationRecord)

    assert_instance_of Dex::Operation::RecordBackend::ActiveRecordAdapter, backend
  end

  def test_backend_returns_nil_when_no_record_class
    backend = Dex::Operation::RecordBackend.for(nil)

    assert_nil backend
  end

  private

  def setup_database
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :operation_records, force: true do |t|
          t.string :name, null: false
          t.json :params, default: {}
          t.datetime :performed_at
          t.timestamps
        end

        create_table :minimal_operation_records, force: true do |t|
          t.string :name, null: false
          t.timestamps
        end
      end
    end

    # Define AR models for tests (only if not already defined)
    Object.const_set(:OperationRecord, Class.new(ActiveRecord::Base)) unless defined?(OperationRecord)
    Object.const_set(:MinimalOperationRecord, Class.new(ActiveRecord::Base)) unless defined?(MinimalOperationRecord)
  end

  def build_operation
    Class.new(Dex::Operation) do
      params { attribute :name, Types::String }
      def perform; end
    end
  end

  def build_named_operation(name)
    op_class = Class.new(Dex::Operation) do
      params { attribute :name, Types::String }
      def perform; end
    end
    Object.const_set(name, op_class)
    op_class
  end
end
