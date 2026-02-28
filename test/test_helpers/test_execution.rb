# frozen_string_literal: true

require "test_helper"
require "dex/test_helpers"

class TestTestExecution < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_call_operation_returns_ok
    op = build_operation { def perform = "hello" }
    result = call_operation(op)
    assert result.ok?
    assert_equal "hello", result.value
  end

  def test_call_operation_returns_err
    op = build_operation do
      error :nope
      def perform = error!(:nope)
    end
    result = call_operation(op)
    assert result.error?
    assert_equal :nope, result.code
  end

  def test_call_operation_with_params
    op = build_operation do
      params { attribute :name, Types::String }
      def perform = "Hi #{name}"
    end
    result = call_operation(op, name: "Alice")
    assert result.ok?
    assert_equal "Hi Alice", result.value
  end

  def test_call_operation_bang_returns_value
    op = build_operation { def perform = 42 }
    assert_equal 42, call_operation!(op)
  end

  def test_call_operation_bang_raises_on_error
    op = build_operation do
      error :broken
      def perform = error!(:broken)
    end
    err = assert_raises(Dex::Error) { call_operation!(op) }
    assert_equal :broken, err.code
  end

  def test_call_operation_bang_with_params
    op = build_operation do
      params { attribute :x, Types::Integer }
      def perform = x * 2
    end
    assert_equal 10, call_operation!(op, x: 5)
  end

  def test_raises_without_subject_or_class
    assert_raises(ArgumentError) { call_operation(name: "test") }
  end
end

class TestTestExecutionWithSubject < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  GreetOp = Class.new(Dex::Operation) do
    params { attribute :name, Types::String }
    def perform = "Hello #{name}"
  end

  testing GreetOp

  def setup
    super
    setup_test_database
  end

  def test_call_operation_uses_subject
    result = call_operation(name: "World")
    assert result.ok?
    assert_equal "Hello World", result.value
  end

  def test_call_operation_bang_uses_subject
    assert_equal "Hello World", call_operation!(name: "World")
  end
end
