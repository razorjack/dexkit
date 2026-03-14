# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestResultAssertions < Minitest::Test
  include Dex::Operation::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_assert_ok
    op = build_operation { def perform = "yes" }
    result = call_operation(op)
    assert_ok result

    err_op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    err_result = call_operation(err_op)
    assert_raises(Minitest::Assertion) { assert_ok err_result }
  end

  def test_assert_ok_with_value
    op = build_operation { def perform = 42 }
    result = call_operation(op)
    assert_ok result, 42
    assert_raises(Minitest::Assertion) { assert_ok result, 99 }
  end

  def test_assert_ok_with_block
    op = build_operation { def perform = "hello" }
    result = call_operation(op)
    yielded = nil
    assert_ok(result) { |val| yielded = val }
    assert_equal "hello", yielded
  end

  def test_refute_ok
    err_op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    refute_ok call_operation(err_op)

    ok_op = build_operation { def perform = "yes" }
    assert_raises(Minitest::Assertion) { refute_ok call_operation(ok_op) }
  end

  def test_assert_err
    err_op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    assert_err call_operation(err_op)

    ok_op = build_operation { def perform = "yes" }
    assert_raises(Minitest::Assertion) { assert_err call_operation(ok_op) }
  end

  def test_assert_err_with_code
    op = build_operation do
      error :not_found
      def perform = error!(:not_found)
    end
    result = call_operation(op)
    assert_err result, :not_found
    assert_raises(Minitest::Assertion) { assert_err result, :invalid }
  end

  def test_assert_err_with_message
    op = build_operation do
      error :fail
      def perform = error!(:fail, "something went wrong")
    end
    result = call_operation(op)
    assert_err result, :fail, message: "something went wrong"
    assert_err result, :fail, message: /went wrong/
  end

  def test_assert_err_with_details
    op = build_operation do
      error :fail
      def perform = error!(:fail, details: { field: "email" })
    end
    result = call_operation(op)
    assert_err result, :fail, details: { field: "email" }
  end

  def test_assert_err_with_block
    op = build_operation do
      error :fail
      def perform = error!(:fail, "oops")
    end
    result = call_operation(op)
    yielded = nil
    assert_err(result, :fail) { |err| yielded = err }
    assert_equal "oops", yielded.message
  end

  def test_refute_err
    ok_op = build_operation { def perform = "yes" }
    refute_err call_operation(ok_op)
    refute_err call_operation(ok_op), :not_found

    err_op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    assert_raises(Minitest::Assertion) { refute_err call_operation(err_op) }

    # refute_err with code: passes for different code, fails for matching code
    multi_op = build_operation do
      error :not_found, :invalid
      def perform = error!(:not_found)
    end
    result = call_operation(multi_op)
    refute_err result, :invalid
    assert_raises(Minitest::Assertion) { refute_err result, :not_found }
  end
end
