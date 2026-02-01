# frozen_string_literal: true

require "test_helper"

class TestOperationTransaction < Minitest::Test
  def setup
    setup_test_database
    Dex.configure { |c| c.transaction_adapter = :active_record }
  end

  def teardown
    Dex.configure { |c| c.transaction_adapter = :active_record }
    super
  end

  def test_transaction_enabled_by_default
    op = build_operation do
      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_transaction_commits_on_success
    op = build_operation do
      def perform
        TestModel.create!(name: "Success")
        "result"
      end
    end

    result = op.new.perform
    assert_equal "result", result
    assert_equal 1, TestModel.count
    assert_equal "Success", TestModel.last.name
  end

  def test_transaction_false_disables
    op = build_operation do
      transaction false

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op.new.perform }
    assert_equal 1, TestModel.count # Record was created despite error
  end

  def test_transaction_true_explicitly_enables
    op = build_operation do
      transaction true

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_transaction_settings_inherit
    parent = build_operation do
      transaction false
    end

    child = build_operation(parent: parent) do
      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { child.new.perform }
    assert_equal 1, TestModel.count # Inherited disabled state
  end

  def test_child_can_reenable_transaction
    parent = build_operation do
      transaction false
    end

    child = build_operation(parent: parent) do
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
    op = build_operation do
      transaction adapter: :active_record

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_transaction_shorthand_adapter_syntax
    op = build_operation do
      transaction :active_record

      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_returns_perform_result
    op = build_operation do
      def perform
        TestModel.create!(name: "Test")
        {status: "success", count: TestModel.count}
      end
    end

    result = op.new.perform
    assert_equal({status: "success", count: 1}, result)
  end

  def test_record_save_inside_transaction
    with_recording do
      op = define_operation(:TestRecordInTransaction) do
        params { attribute :name, Types::String }
        def perform
          TestModel.create!(name: "TestModel")
          raise "Error"
        end
      end

      assert_raises(RuntimeError) { op.new(name: "Test").perform }

      # Both operation record and test model should be rolled back
      assert_equal 0, OperationRecord.count
      assert_equal 0, TestModel.count
    end
  end

  def test_multiple_database_operations_in_transaction
    op = build_operation do
      def perform
        TestModel.create!(name: "First")
        TestModel.create!(name: "Second")
        TestModel.create!(name: "Third")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_nested_operations_share_transaction
    inner_op = build_operation do
      def perform
        TestModel.create!(name: "Inner")
      end
    end

    outer_op = build_operation do
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

    op = build_operation do
      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_unknown_adapter_raises_error
    error = assert_raises(ArgumentError) do
      build_operation do
        transaction :unknown_adapter
      end.new.perform
    end

    assert_match(/Unknown transaction adapter/, error.message)
  end
end
