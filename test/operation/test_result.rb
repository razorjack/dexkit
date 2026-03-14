# frozen_string_literal: true

require "test_helper"

class TestOperationResult < Minitest::Test
  def setup
    setup_test_database
  end

  # success Type declaration and inheritance

  def test_success_type_declaration_and_inheritance
    # Stored
    op = build_operation {}
    op.success(String)
    assert_equal String, op._success_type

    # Inherits from parent
    parent = build_operation {}
    parent.success(Integer)
    child = Class.new(parent)
    assert_equal Integer, child._success_type

    # Child overrides parent
    child.success(String)
    assert_equal String, child._success_type
    assert_equal Integer, parent._success_type
  end

  def test_success_type_nil_when_not_declared
    op = build_operation {}
    assert_nil op._success_type
  end

  # error :codes declaration and inheritance

  def test_error_codes_declaration_and_inheritance
    # Stored
    op = build_operation {}
    op.error(:not_found, :invalid)
    assert_equal %i[not_found invalid], op._declared_errors

    # Inherits and deduplicates
    parent = build_operation {}
    parent.error(:not_found)
    child = Class.new(parent)
    child.error(:not_found, :invalid)
    assert_equal %i[not_found invalid], child._declared_errors
    assert_equal %i[not_found], parent._declared_errors
  end

  def test_has_declared_errors_false_when_empty
    op = build_operation {}
    refute op._has_declared_errors?
  end

  def test_has_declared_errors_true_when_declared
    op = build_operation {}
    op.error(:not_found)

    assert op._has_declared_errors?
  end

  # error! validation behavior

  def test_error_bang_accepts_declared_code
    op = build_operation do
      def perform
        error!(:not_found, "Missing")
      end
    end
    op.error(:not_found)

    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :not_found, err.code
  end

  def test_error_bang_rejects_undeclared_code
    op = build_operation do
      def perform
        error!(:surprise)
      end
    end
    op.error(:not_found)

    assert_raises(ArgumentError) { op.new.call }
  end

  def test_error_bang_accepts_any_code_without_declaration
    op = build_operation do
      def perform
        error!(:anything_goes)
      end
    end

    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :anything_goes, err.code
  end

  # Operations without declarations work unchanged

  def test_operation_without_declarations_returns_value
    op = operation { "hello" }
    assert_equal "hello", op.new.call
  end

  def test_operation_without_declarations_returns_hash
    op = operation { { id: 1, name: "Test" } }
    result = op.new.call
    assert_equal({ id: 1, name: "Test" }, result)
  end

  # success type runtime validation

  def test_success_type_validation
    # Correct type accepted
    op1 = operation(success: String) { "hello" }
    assert_equal "hello", op1.new.call

    # Wrong type rejected
    op2 = operation(success: String) { 123 }
    assert_raises(ArgumentError) { op2.new.call }

    # Nil return skips validation
    op3 = operation(success: String) { nil }
    assert_nil op3.new.call
  end

  def test_success_type_validates_ref_type
    model = TestModel.create!(name: "test")
    op = operation(success: Dex::RefType.new(TestModel)) { model }
    assert_equal model, op.new.call
  end

  def test_success_type_rejects_wrong_ref_type
    op = operation(success: Dex::RefType.new(TestModel)) { { id: 1 } }
    assert_raises(ArgumentError) { op.new.call }
  end

  def test_success_type_no_declaration_skips_validation
    op = operation { 42 }
    assert_equal 42, op.new.call
  end

  def test_success_optional_type
    # Accepts correct type
    op1 = build_operation do
      success _Nilable(String)
      def perform = "hello"
    end
    assert_equal "hello", op1.new.call

    # Rejects wrong type
    op2 = build_operation do
      success _Nilable(String)
      def perform = 123
    end
    assert_raises(ArgumentError) { op2.new.call }

    # Accepts nil
    op3 = build_operation do
      success _Nilable(String)
      def perform = nil
    end
    assert_nil op3.new.call
  end

  def test_success_type_validates_success_bang
    op = operation(success: String) do
      success!(123)
    end
    assert_raises(ArgumentError) { op.new.call }
  end
end
