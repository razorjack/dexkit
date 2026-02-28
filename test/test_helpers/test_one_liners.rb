# frozen_string_literal: true

require "test_helper"
require "dex/test_helpers"

class TestOneLinerAssertions < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  # assert_operation

  def test_assert_operation_with_explicit_class
    op = build_operation { def perform = "ok" }
    result = assert_operation(op)
    assert result.ok?
  end

  def test_assert_operation_with_params
    op = build_operation do
      prop :name, String
      def perform = "Hi #{name}"
    end
    result = assert_operation(op, name: "Alice")
    assert_equal "Hi Alice", result.value
  end

  def test_assert_operation_with_returns
    op = build_operation { def perform = 42 }
    assert_operation(op, returns: 42)
  end

  def test_assert_operation_fails_on_error
    op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    assert_raises(Minitest::Assertion) { assert_operation(op) }
  end

  def test_assert_operation_fails_on_wrong_return
    op = build_operation { def perform = 42 }
    assert_raises(Minitest::Assertion) { assert_operation(op, returns: 99) }
  end

  # assert_operation_error

  def test_assert_operation_error_with_class_and_code
    op = build_operation do
      error :not_found
      def perform = error!(:not_found)
    end
    result = assert_operation_error(op, :not_found)
    assert result.error?
  end

  def test_assert_operation_error_with_params
    op = build_operation do
      prop :name, String
      error :invalid
      define_method(:perform) do
        error!(:invalid, "bad name") if name == "bad"
        name
      end
    end
    assert_operation_error(op, :invalid, name: "bad")
  end

  def test_assert_operation_error_with_message
    op = build_operation do
      error :fail
      def perform = error!(:fail, "it broke")
    end
    assert_operation_error(op, :fail, message: "it broke")
  end

  def test_assert_operation_error_with_message_regex
    op = build_operation do
      error :fail
      def perform = error!(:fail, "something went wrong")
    end
    assert_operation_error(op, :fail, message: /went wrong/)
  end

  def test_assert_operation_error_fails_on_success
    op = build_operation { def perform = "ok" }
    assert_raises(Minitest::Assertion) { assert_operation_error(op, :nope) }
  end

  def test_assert_operation_error_fails_on_wrong_code
    op = build_operation do
      error :not_found, :invalid
      def perform = error!(:not_found)
    end
    assert_raises(Minitest::Assertion) { assert_operation_error(op, :invalid) }
  end
end

class TestOneLinerWithSubject < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  SimpleOp = Class.new(Dex::Operation) do
    prop :value, Integer
    error :negative
    def perform
      error!(:negative) if value < 0
      value * 2
    end
  end

  testing SimpleOp

  def setup
    super
    setup_test_database
  end

  def test_assert_operation_uses_subject
    assert_operation(value: 5, returns: 10)
  end

  def test_assert_operation_error_uses_subject
    assert_operation_error(:negative, value: -1)
  end
end
