# frozen_string_literal: true

require "test_helper"

class TestOperationMongoidTransaction < Minitest::Test
  def setup
    setup_mongoid_operation_database
    skip "MongoDB replica set is required for Mongoid transaction tests." unless mongoid_transactions_supported?

    Dex.configure { |c| c.transaction_adapter = :mongoid }
  end

  def teardown
    Dex.configure { |c| c.transaction_adapter = nil }
    super
  end

  def test_transaction_rolls_back_on_exception
    op = build_operation do
      def perform
        MongoTestModel.create!(name: "rollback")
        raise "boom"
      end
    end

    assert_raises(RuntimeError) { op.new.call }
    assert_equal 0, MongoTestModel.count
  end

  def test_transaction_false_disables_mongoid_wrap
    op = build_operation do
      transaction false

      def perform
        MongoTestModel.create!(name: "no_txn")
        raise "boom"
      end
    end

    assert_raises(RuntimeError) { op.new.call }
    assert_equal 1, MongoTestModel.count
  end

  def test_transaction_adapter_can_be_overridden_per_operation
    Dex.configure { |c| c.transaction_adapter = nil }

    op = build_operation do
      transaction :mongoid

      def perform
        MongoTestModel.create!(name: "override")
        raise "boom"
      end
    end

    assert_raises(RuntimeError) { op.new.call }
    assert_equal 0, MongoTestModel.count
  end

  def test_after_commit_runs_only_after_successful_commit
    log = []

    op = build_operation do
      define_method(:perform) do
        MongoTestModel.create!(name: "after_commit")
        after_commit { log << :committed }
        log << :perform_done
      end
    end

    op.new.call

    assert_equal %i[perform_done committed], log
    assert_equal 1, MongoTestModel.count
  end

  def test_after_commit_does_not_run_when_operation_errors
    log = []

    op = build_operation do
      error :invalid

      define_method(:perform) do
        MongoTestModel.create!(name: "no_commit")
        after_commit { log << :committed }
        error!(:invalid)
      end
    end

    assert_raises(Dex::Error) { op.new.call }
    assert_empty log
    assert_equal 0, MongoTestModel.count
  end

  def test_nested_operations_defer_after_commit_until_outermost_commit
    log = []

    inner = build_operation do
      define_method(:perform) do
        MongoTestModel.create!(name: "inner")
        after_commit { log << :inner_committed }
      end
    end

    outer = build_operation do
      define_method(:perform) do
        MongoTestModel.create!(name: "outer")
        after_commit { log << :outer_committed }
        inner.new.call
        log << :outer_done
      end
    end

    outer.new.call

    assert_equal %i[outer_done outer_committed inner_committed], log
    assert_equal 2, MongoTestModel.count
  end

  def test_nested_callbacks_are_discarded_when_outer_operation_rolls_back
    log = []

    inner = build_operation do
      define_method(:perform) do
        MongoTestModel.create!(name: "inner")
        after_commit { log << :inner_committed }
      end
    end

    outer = build_operation do
      define_method(:perform) do
        MongoTestModel.create!(name: "outer")
        after_commit { log << :outer_committed }
        inner.new.call
        raise "boom"
      end
    end

    assert_raises(RuntimeError) { outer.new.call }
    assert_empty log
    assert_equal 0, MongoTestModel.count
  end
end
