# frozen_string_literal: true

require "test_helper"
require "dex/test_helpers"

class TestBatchAssertions < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  # assert_all_succeed

  def test_assert_all_succeed_passes
    op = build_operation do
      prop :x, Integer
      def perform = x * 2
    end

    results = assert_all_succeed(op, params_list: [{ x: 1 }, { x: 2 }, { x: 3 }])
    assert_equal 3, results.size
    assert results.all?(&:ok?)
  end

  def test_assert_all_succeed_fails_on_any_error
    op = build_operation do
      prop :x, Integer
      error :negative
      def perform
        error!(:negative) if x < 0
        x
      end
    end

    assert_raises(Minitest::Assertion) do
      assert_all_succeed(op, params_list: [{ x: 1 }, { x: -1 }, { x: 2 }])
    end
  end

  # assert_all_fail

  def test_assert_all_fail_passes
    op = build_operation do
      prop :x, Integer
      error :negative
      def perform
        error!(:negative) if x < 0
        x
      end
    end

    results = assert_all_fail(op, code: :negative, params_list: [{ x: -1 }, { x: -2 }])
    assert_equal 2, results.size
    assert results.all?(&:error?)
  end

  def test_assert_all_fail_fails_on_success
    op = build_operation do
      prop :x, Integer
      error :negative
      def perform
        error!(:negative) if x < 0
        x
      end
    end

    assert_raises(Minitest::Assertion) do
      assert_all_fail(op, code: :negative, params_list: [{ x: -1 }, { x: 1 }])
    end
  end

  def test_assert_all_fail_checks_message_string
    op = build_operation do
      prop :x, Integer
      error :negative
      def perform
        error!(:negative, "bad value") if x < 0
        x
      end
    end

    assert_all_fail(op, code: :negative, message: "bad value", params_list: [{ x: -1 }, { x: -2 }])
  end

  def test_assert_all_fail_checks_message_regexp
    op = build_operation do
      prop :x, Integer
      error :negative
      def perform
        error!(:negative, "bad value") if x < 0
        x
      end
    end

    assert_all_fail(op, code: :negative, message: /bad/, params_list: [{ x: -1 }, { x: -2 }])
  end

  def test_assert_all_fail_fails_on_message_mismatch
    op = build_operation do
      prop :x, Integer
      error :negative
      def perform
        error!(:negative, "bad value") if x < 0
        x
      end
    end

    assert_raises(Minitest::Assertion) do
      assert_all_fail(op, code: :negative, message: "wrong", params_list: [{ x: -1 }])
    end
  end

  def test_assert_all_fail_checks_details
    op = build_operation do
      prop :x, Integer
      error :negative
      def perform
        error!(:negative, details: { field: "x" }) if x < 0
        x
      end
    end

    assert_all_fail(op, code: :negative, details: { field: "x" }, params_list: [{ x: -1 }, { x: -2 }])
  end

  def test_assert_all_fail_fails_on_details_mismatch
    op = build_operation do
      prop :x, Integer
      error :negative
      def perform
        error!(:negative, details: { field: "x" }) if x < 0
        x
      end
    end

    assert_raises(Minitest::Assertion) do
      assert_all_fail(op, code: :negative, details: { field: "y" }, params_list: [{ x: -1 }])
    end
  end

  def test_assert_all_fail_fails_on_wrong_code
    op = build_operation do
      prop :x, Integer
      error :negative, :zero
      def perform
        error!(:zero) if x == 0
        error!(:negative) if x < 0
        x
      end
    end

    assert_raises(Minitest::Assertion) do
      assert_all_fail(op, code: :negative, params_list: [{ x: -1 }, { x: 0 }])
    end
  end
end
