# frozen_string_literal: true

require "test_helper"
require "mongoid"

class TestOperationMongoidTransactionGuards < Minitest::Test
  def test_after_commit_is_fiber_local
    log = []

    op = build_operation do
      transaction false
      prop :tag, String

      define_method(:perform) do
        after_commit { log << :"#{tag}_committed" }
        log << :"#{tag}_before_yield"
        Fiber.yield
        log << :"#{tag}_after_yield"
      end
    end

    first = Fiber.new { op.new(tag: "one").call }
    second = Fiber.new { op.new(tag: "two").call }

    first.resume
    second.resume
    assert_equal %i[one_before_yield two_before_yield], log

    second.resume
    assert_equal %i[one_before_yield two_before_yield two_after_yield two_committed], log

    first.resume
    assert_equal %i[
      one_before_yield
      two_before_yield
      two_after_yield
      two_committed
      one_after_yield
      one_committed
    ], log
  end

  def test_after_commit_raises_for_ambient_mongoid_transaction_without_dex_adapter
    op = build_operation do
      transaction false

      def perform
        after_commit { :ok }
      end
    end

    Dex::Operation::TransactionAdapter.stub :ambient_mongoid_transaction?, true do
      error = assert_raises(RuntimeError) { op.new.call }
      assert_match(/ambient Mongoid\.transaction/, error.message)
    end
  end

  def test_mongoid_after_commit_raises_for_ambient_transaction_opened_outside_dex
    Dex::Operation::TransactionAdapter.stub :ambient_mongoid_transaction?, true do
      error = assert_raises(RuntimeError) do
        Dex::Operation::TransactionAdapter::MongoidAdapter.after_commit { :ok }
      end

      assert_match(/ambient Mongoid\.transaction/, error.message)
    end
  end

  def test_explicit_mongoid_transaction_raises_prescriptive_error_when_transactions_are_unsupported
    op = build_operation do
      transaction :mongoid

      def perform
        :ok
      end
    end

    Mongoid.stub :transaction, ->(*) { raise Mongoid::Errors::TransactionsNotSupported } do
      error = assert_raises(RuntimeError) { op.new.call }
      assert_match(/replica set or sharded cluster/, error.message)
    end
  end
end
