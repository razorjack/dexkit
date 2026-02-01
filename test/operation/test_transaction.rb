# frozen_string_literal: true

require "test_helper"

class TestOperationTransaction < Minitest::Test
  def setup
    setup_database
    Dex.configure do |c|
      c.transaction_adapter = :active_record
    end
  end

  def teardown
    Dex.configure do |c|
      c.transaction_adapter = :active_record
    end
  end

  def test_transaction_enabled_by_default
    op_class = Class.new(Dex::Operation) do
      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op_class.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_transaction_commits_on_success
    op_class = Class.new(Dex::Operation) do
      def perform
        TestModel.create!(name: "Success")
        "result"
      end
    end

    result = op_class.new.perform
    assert_equal "result", result
    assert_equal 1, TestModel.count
    assert_equal "Success", TestModel.last.name
  end

  def test_transaction_false_disables
    op_class = Class.new(Dex::Operation) do
      transaction false

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op_class.new.perform }
    assert_equal 1, TestModel.count # Record was created despite error
  end

  def test_transaction_true_explicitly_enables
    op_class = Class.new(Dex::Operation) do
      transaction true

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op_class.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_transaction_settings_inherit
    parent = Class.new(Dex::Operation) do
      transaction false
    end

    child = Class.new(parent) do
      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { child.new.perform }
    assert_equal 1, TestModel.count # Inherited disabled state
  end

  def test_child_can_reenable_transaction
    parent = Class.new(Dex::Operation) do
      transaction false
    end

    child = Class.new(parent) do
      transaction true

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { child.new.perform }
    assert_equal 0, TestModel.count # Child re-enabled transaction
  end

  def test_transaction_adapter_override
    op_class = Class.new(Dex::Operation) do
      transaction adapter: :active_record

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op_class.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_transaction_shorthand_adapter_syntax
    op_class = Class.new(Dex::Operation) do
      transaction :active_record

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op_class.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_returns_perform_result
    op_class = Class.new(Dex::Operation) do
      def perform
        TestModel.create!(name: "Test")
        { status: "success", count: TestModel.count }
      end
    end

    result = op_class.new.perform
    assert_equal({ status: "success", count: 1 }, result)
  end

  def test_record_save_inside_transaction
    Dex.configure { |c| c.record_class = OperationRecord }
    Dex.reset_record_backend!

    op_class = build_named_operation(:TestRecordInTransaction)

    begin
      op_class.new(name: "Test").perform
    rescue
      # Swallow error
    end

    # Both operation record and test model should be rolled back
    assert_equal 0, OperationRecord.count
    assert_equal 0, TestModel.count
  ensure
    Object.send(:remove_const, :TestRecordInTransaction) if defined?(TestRecordInTransaction)
    Dex.configure { |c| c.record_class = nil }
    Dex.reset_record_backend!
  end

  def test_multiple_database_operations_in_transaction
    op_class = Class.new(Dex::Operation) do
      def perform
        TestModel.create!(name: "First")
        TestModel.create!(name: "Second")
        TestModel.create!(name: "Third")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op_class.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_nested_operations_share_transaction
    inner_op = Class.new(Dex::Operation) do
      def perform
        TestModel.create!(name: "Inner")
      end
    end

    outer_op = Class.new(Dex::Operation) do
      define_method(:perform) do
        TestModel.create!(name: "Outer")
        inner_op.new.perform
        raise "Error in outer"
      end
    end

    assert_raises(RuntimeError) { outer_op.new.perform }
    assert_equal 0, TestModel.count # Both should be rolled back
  end

  def test_global_transaction_adapter_config
    Dex.configure { |c| c.transaction_adapter = :active_record }

    op_class = Class.new(Dex::Operation) do
      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op_class.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_unknown_adapter_raises_error
    error = assert_raises(ArgumentError) do
      Class.new(Dex::Operation) do
        transaction :unknown_adapter
      end.new.perform
    end

    assert_match(/Unknown transaction adapter/, error.message)
  end

  private

  def setup_database
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :test_models, force: true do |t|
          t.string :name, null: false
          t.timestamps
        end

        create_table :operation_records, force: true do |t|
          t.string :name, null: false
          t.json :params, default: {}
          t.datetime :performed_at
          t.timestamps
        end
      end
    end

    Object.const_set(:TestModel, Class.new(ActiveRecord::Base)) unless defined?(TestModel)
    Object.const_set(:OperationRecord, Class.new(ActiveRecord::Base)) unless defined?(OperationRecord)
  end

  def build_named_operation(name)
    op_class = Class.new(Dex::Operation) do
      params { attribute :name, Types::String }
      def perform
        TestModel.create!(name: "TestModel")
        raise "Error"
      end
    end
    Object.const_set(name, op_class)
    op_class
  end
end
