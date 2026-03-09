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

  # assert_ok

  def test_assert_ok_passes_for_ok
    op = build_operation { def perform = "yes" }
    result = call_operation(op)
    assert_ok result
  end

  def test_assert_ok_fails_for_err
    op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    result = call_operation(op)
    assert_raises(Minitest::Assertion) { assert_ok result }
  end

  def test_assert_ok_with_expected_value
    op = build_operation { def perform = 42 }
    result = call_operation(op)
    assert_ok result, 42
  end

  def test_assert_ok_with_wrong_expected_value
    op = build_operation { def perform = 42 }
    result = call_operation(op)
    assert_raises(Minitest::Assertion) { assert_ok result, 99 }
  end

  def test_assert_ok_with_block
    op = build_operation { def perform = "hello" }
    result = call_operation(op)
    yielded = nil
    assert_ok(result) { |val| yielded = val }
    assert_equal "hello", yielded
  end

  # refute_ok

  def test_refute_ok_passes_for_err
    op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    result = call_operation(op)
    refute_ok result
  end

  def test_refute_ok_fails_for_ok
    op = build_operation { def perform = "yes" }
    result = call_operation(op)
    assert_raises(Minitest::Assertion) { refute_ok result }
  end

  # assert_err

  def test_assert_err_passes_for_err
    op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    result = call_operation(op)
    assert_err result
  end

  def test_assert_err_fails_for_ok
    op = build_operation { def perform = "yes" }
    result = call_operation(op)
    assert_raises(Minitest::Assertion) { assert_err result }
  end

  def test_assert_err_with_code
    op = build_operation do
      error :not_found
      def perform = error!(:not_found)
    end
    result = call_operation(op)
    assert_err result, :not_found
  end

  def test_assert_err_with_wrong_code
    op = build_operation do
      error :not_found
      def perform = error!(:not_found)
    end
    result = call_operation(op)
    assert_raises(Minitest::Assertion) { assert_err result, :invalid }
  end

  def test_assert_err_with_message_string
    op = build_operation do
      error :fail
      def perform = error!(:fail, "oops")
    end
    result = call_operation(op)
    assert_err result, :fail, message: "oops"
  end

  def test_assert_err_with_message_regex
    op = build_operation do
      error :fail
      def perform = error!(:fail, "something went wrong")
    end
    result = call_operation(op)
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

  # refute_err

  def test_refute_err_passes_for_ok
    op = build_operation { def perform = "yes" }
    result = call_operation(op)
    refute_err result
  end

  def test_refute_err_fails_for_err
    op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    result = call_operation(op)
    assert_raises(Minitest::Assertion) { refute_err result }
  end

  def test_refute_err_with_code_passes_for_different_code
    op = build_operation do
      error :not_found, :invalid
      def perform = error!(:not_found)
    end
    result = call_operation(op)
    refute_err result, :invalid
  end

  def test_refute_err_with_code_passes_for_ok
    op = build_operation { def perform = "yes" }
    result = call_operation(op)
    refute_err result, :not_found
  end

  def test_refute_err_with_code_fails_for_matching_code
    op = build_operation do
      error :not_found
      def perform = error!(:not_found)
    end
    result = call_operation(op)
    assert_raises(Minitest::Assertion) { refute_err result, :not_found }
  end
end
