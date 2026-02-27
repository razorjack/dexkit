# frozen_string_literal: true

require "test_helper"

class TestOperationAssert < Minitest::Test
  def setup
    setup_test_database
  end

  # Block form

  def test_block_form_returns_value_when_truthy
    op = operation do
      assert!(:not_found) { "hello" }
    end

    assert_equal "hello", op.new.call
  end

  def test_block_form_errors_when_block_returns_nil
    op = operation(errors: [:not_found]) do
      assert!(:not_found) { nil }
    end

    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :not_found, err.code
  end

  def test_block_form_errors_when_block_returns_false
    op = operation(errors: [:not_found]) do
      assert!(:not_found) { false }
    end

    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :not_found, err.code
  end

  # Value form

  def test_value_form_returns_value_when_truthy
    op = operation do
      assert!("hello", :not_found)
    end

    assert_equal "hello", op.new.call
  end

  def test_value_form_errors_when_value_is_nil
    op = operation(errors: [:not_found]) do
      assert!(nil, :not_found)
    end

    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :not_found, err.code
  end

  def test_value_form_errors_when_value_is_false
    op = operation(errors: [:not_found]) do
      assert!(false, :not_found)
    end

    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :not_found, err.code
  end

  # Error code validation

  def test_respects_declared_error_codes
    op = operation(errors: [:not_found]) do
      assert!(nil, :undeclared)
    end

    assert_raises(ArgumentError) { op.new.call }
  end

  def test_accepts_undeclared_code_when_no_errors_declared
    op = operation do
      assert!(nil, :anything)
    end

    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :anything, err.code
  end

  # Safe modifier

  def test_works_with_safe_modifier_on_success
    op = operation do
      assert!(:not_found) { 42 }
    end

    result = op.new.safe.call
    assert result.ok?
    assert_equal 42, result.value
  end

  def test_works_with_safe_modifier_on_failure
    op = operation do
      assert!(:not_found) { nil }
    end

    result = op.new.safe.call
    assert result.error?
    assert_equal :not_found, result.code
  end

  # Transaction rollback

  def test_rolls_back_transaction_on_assertion_failure
    op = build_operation do
      def perform
        TestModel.create!(name: "should-rollback")
        assert!(:not_found) { nil }
      end
    end

    assert_raises(Dex::Error) { op.new.call }
    assert_equal 0, TestModel.count
  end
end
