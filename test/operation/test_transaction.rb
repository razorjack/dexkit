# frozen_string_literal: true

require "test_helper"

class TestOperationTransaction < Minitest::Test
  def setup
    setup_test_database
    Dex.configure { |c| c.transaction_adapter = :active_record }
  end

  def teardown
    Dex.configure { |c| c.transaction_adapter = nil }
    super
  end

  def test_transaction_enabled_by_default
    op = build_operation do
      def perform
        TestModel.create!(name: "Test")
        raise "Error"
      end
    end

    assert_raises(RuntimeError) { op.new.call }
    assert_equal 0, TestModel.count
  end

  def test_transaction_commits_on_success
    op = build_operation do
      def perform
        TestModel.create!(name: "Success")
        "result"
      end
    end

    result = op.new.call
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

    assert_raises(RuntimeError) { op.new.call }
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

    assert_raises(RuntimeError) { op.new.call }
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

    assert_raises(RuntimeError) { child.new.call }
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

    assert_raises(RuntimeError) { child.new.call }
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

    assert_raises(RuntimeError) { op.new.call }
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

    assert_raises(RuntimeError) { op.new.call }
    assert_equal 0, TestModel.count
  end

  def test_returns_perform_result
    op = build_operation do
      def perform
        TestModel.create!(name: "Test")
        { status: "success", count: TestModel.count }
      end
    end

    result = op.new.call
    assert_equal({ status: "success", count: 1 }, result)
  end

  def test_record_save_outside_transaction
    with_recording do
      op = define_operation(:TestRecordOutsideTransaction) do
        prop :name, String
        def perform
          TestModel.create!(name: "TestModel")
          raise "Error"
        end
      end

      assert_raises(RuntimeError) { op.new(name: "Test").call }

      # Test model rolled back, but operation record persists (recorded outside transaction)
      assert_equal 1, OperationRecord.count
      assert_equal "failed", OperationRecord.last.status
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

    assert_raises(RuntimeError) { op.new.call }
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
        inner_op.new.call
        raise "Error in outer"
      end
    end

    assert_raises(RuntimeError) { outer_op.new.call }
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

    assert_raises(RuntimeError) { op.new.call }
    assert_equal 0, TestModel.count
  end

  def test_detect_returns_nil_without_active_record_connection_pool
    ActiveRecord::Base.connection_handler.clear_all_connections!
    ActiveRecord::Base.remove_connection

    assert_nil Dex::Operation::TransactionAdapter.detect
  end

  def test_unknown_adapter_raises_error
    error = assert_raises(ArgumentError) do
      build_operation do
        transaction :unknown_adapter
      end
    end

    assert_match(/unknown transaction adapter/, error.message)
  end

  def test_unknown_global_adapter_raises_error_at_assignment
    error = assert_raises(ArgumentError) do
      Dex.configure { |c| c.transaction_adapter = :mongoid }
    end

    assert_match(/unknown transaction adapter/, error.message)
  end

  # after_commit

  def test_after_commit_runs_after_transaction_commits
    log = []

    op = build_operation do
      define_method(:perform) do
        TestModel.create!(name: "Test")
        after_commit { log << :committed }
        log << :perform_done
      end
    end

    op.new.call
    assert_equal %i[perform_done committed], log
    assert_equal 1, TestModel.count
  end

  def test_after_commit_does_not_run_on_error_halt
    log = []

    op = build_operation do
      error :something_wrong

      define_method(:perform) do
        after_commit { log << :committed }
        error!(:something_wrong)
      end
    end

    assert_raises(Dex::Error) { op.new.call }
    assert_empty log
  end

  def test_after_commit_does_not_run_on_exception
    log = []

    op = build_operation do
      define_method(:perform) do
        after_commit { log << :committed }
        raise "boom"
      end
    end

    assert_raises(RuntimeError) { op.new.call }
    assert_empty log
  end

  def test_after_commit_deferred_without_transaction
    log = []

    op = build_operation do
      transaction false

      define_method(:perform) do
        after_commit { log << :deferred }
        log << :after_call
      end
    end

    op.new.call
    assert_equal %i[after_call deferred], log
  end

  def test_after_commit_not_run_on_error_halt_without_transaction
    log = []

    op = build_operation do
      transaction false
      error :boom

      define_method(:perform) do
        after_commit { log << :committed }
        error!(:boom)
      end
    end

    assert_raises(Dex::Error) { op.new.call }
    assert_empty log
  end

  def test_after_commit_not_run_on_exception_without_transaction
    log = []

    op = build_operation do
      transaction false

      define_method(:perform) do
        after_commit { log << :committed }
        raise "boom"
      end
    end

    assert_raises(RuntimeError) { op.new.call }
    assert_empty log
  end

  def test_after_commit_nested_non_transactional_flushes_at_outermost
    Dex.configure { |c| c.transaction_adapter = nil }
    log = []

    inner_op = build_operation do
      transaction false

      define_method(:perform) do
        after_commit { log << :inner_committed }
        log << :inner_done
      end
    end

    outer_op = build_operation do
      transaction false

      define_method(:perform) do
        inner_op.new.call
        after_commit { log << :outer_committed }
        log << :outer_done
      end
    end

    outer_op.new.call
    assert_equal %i[inner_done outer_done inner_committed outer_committed], log
  end

  def test_after_commit_nested_non_transactional_discarded_on_outer_error
    Dex.configure { |c| c.transaction_adapter = nil }
    log = []

    inner_op = build_operation do
      transaction false

      define_method(:perform) do
        after_commit { log << :inner_committed }
      end
    end

    outer_op = build_operation do
      transaction false

      define_method(:perform) do
        inner_op.new.call
        raise "outer failed"
      end
    end

    assert_raises(RuntimeError) { outer_op.new.call }
    assert_empty log
  end

  def test_after_commit_multiple_callbacks_run_in_order
    log = []

    op = build_operation do
      define_method(:perform) do
        after_commit { log << :first }
        after_commit { log << :second }
        after_commit { log << :third }
      end
    end

    op.new.call
    assert_equal %i[first second third], log
  end

  def test_after_commit_has_access_to_operation_context
    op = build_operation do
      prop :name, String

      define_method(:perform) do
        @user_name = name.upcase
        after_commit { TestModel.create!(name: @user_name) }
      end
    end

    op.new(name: "alice").call
    assert_equal 1, TestModel.count
    assert_equal "ALICE", TestModel.last.name
  end

  def test_after_commit_requires_block
    op = build_operation do
      define_method(:perform) do
        after_commit
      end
    end

    error = assert_raises(ArgumentError) { op.new.call }
    assert_match(/after_commit requires a block/, error.message)
  end

  def test_after_commit_runs_on_success_halt
    log = []

    op = build_operation do
      define_method(:perform) do
        TestModel.create!(name: "Test")
        after_commit { log << :committed }
        success!("done")
      end
    end

    result = op.new.call
    assert_equal "done", result
    assert_equal [:committed], log
    assert_equal 1, TestModel.count
  end

  def test_after_commit_in_nested_operation_runs_after_outermost_commit
    log = []

    inner_op = build_operation do
      define_method(:perform) do
        TestModel.create!(name: "Inner")
        after_commit { log << :inner_committed }
      end
    end

    outer_op = build_operation do
      define_method(:perform) do
        TestModel.create!(name: "Outer")
        inner_op.new.call
        after_commit { log << :outer_committed }
        log << :outer_perform_done
      end
    end

    outer_op.new.call
    assert_equal %i[outer_perform_done inner_committed outer_committed], log
    assert_equal 2, TestModel.count
  end

  def test_after_commit_in_nested_operation_discarded_on_outer_rollback
    log = []

    inner_op = build_operation do
      define_method(:perform) do
        TestModel.create!(name: "Inner")
        after_commit { log << :inner_committed }
      end
    end

    outer_op = build_operation do
      define_method(:perform) do
        inner_op.new.call
        raise "outer failed"
      end
    end

    assert_raises(RuntimeError) { outer_op.new.call }
    assert_empty log
    assert_equal 0, TestModel.count
  end

  def test_after_commit_deferred_when_inner_has_transaction_false
    log = []

    inner_op = build_operation do
      transaction false

      define_method(:perform) do
        after_commit { log << :inner_committed }
        log << :inner_done
      end
    end

    outer_op = build_operation do
      define_method(:perform) do
        inner_op.new.call
        log << :outer_done
      end
    end

    outer_op.new.call
    assert_equal %i[inner_done outer_done inner_committed], log
  end

  def test_after_commit_discarded_when_inner_has_transaction_false_and_outer_rolls_back
    log = []

    inner_op = build_operation do
      transaction false

      define_method(:perform) do
        after_commit { log << :inner_committed }
      end
    end

    outer_op = build_operation do
      define_method(:perform) do
        inner_op.new.call
        raise "outer failed"
      end
    end

    assert_raises(RuntimeError) { outer_op.new.call }
    assert_empty log
  end

  def test_after_commit_respects_ambient_transaction_rollback
    log = []

    op = build_operation do
      define_method(:perform) do
        TestModel.create!(name: "Test")
        after_commit { log << :committed }
      end
    end

    ActiveRecord::Base.transaction do
      op.new.call
      raise ActiveRecord::Rollback
    end

    assert_empty log
    assert_equal 0, TestModel.count
  end

  def test_after_commit_fires_directly_on_non_transactional_op
    log = []

    op = build_operation do
      transaction false

      define_method(:perform) do
        after_commit { log << :committed }
      end
    end

    op.new.call

    assert_equal [:committed], log
  end

  def test_after_commit_ignores_ambient_transaction_on_non_transactional_op
    log = []

    op = build_operation do
      transaction false

      define_method(:perform) do
        after_commit { log << :committed }
      end
    end

    ActiveRecord::Base.transaction do
      op.new.call
      raise ActiveRecord::Rollback
    end

    assert_equal [:committed], log
  end
end
