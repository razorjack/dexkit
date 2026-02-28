# frozen_string_literal: true

require "test_helper"

class TestOperationClassCall < Minitest::Test
  include OperationHelpers

  def setup
    setup_test_database
  end

  def test_class_call_with_params
    op = operation(params: { name: String }) { name }
    assert_equal "Alice", op.call(name: "Alice")
  end

  def test_class_call_without_params
    op = operation { 42 }
    assert_equal 42, op.call
  end

  def test_class_call_raises_dex_error
    op = operation { error! :boom }
    assert_raises(Dex::Error) { op.call }
  end

  def test_class_call_is_inherited
    parent = operation(params: { x: Integer }) { x + 1 }
    child = Class.new(parent)
    assert_equal 6, child.call(x: 5)
  end

  def test_class_call_equivalent_to_new_call
    op = operation(params: { n: Integer }) { n * n }
    assert_equal op.new(n: 7).call, op.call(n: 7)
  end
end
