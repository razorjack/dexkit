# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestAsyncAssertions < Minitest::Test
  include Dex::Operation::TestHelpers
  include ActiveJob::TestHelper
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_assert_enqueues_operation
    op = define_operation(:AsyncTestOp) do
      prop :name, String
      def perform = name
    end

    assert_enqueues_operation(op, name: "Alice")
  end

  def test_refute_enqueues_operation
    refute_enqueues_operation { "nothing happens" }

    op = define_operation(:AsyncTestOp2) do
      prop :name, String
      def perform = name
    end

    assert_raises(Minitest::Assertion) do
      refute_enqueues_operation do
        op.new(name: "Alice").async.call
      end
    end
  end

  def test_assert_enqueues_operation_with_record_strategy
    op = define_operation(:AsyncRecordOp) do
      prop :name, String
      def perform = name
    end

    with_recording do
      assert_enqueues_operation(op, name: "Alice")
    end
  end
end
