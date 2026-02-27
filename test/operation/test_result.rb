# frozen_string_literal: true

require "test_helper"

class TestOperationResult < Minitest::Test
  def setup
    setup_test_database
  end

  # success Type declaration

  def test_success_type_is_stored
    op = build_operation {}
    op.success(Types::String)

    assert_equal Types::String, op._success_type
  end

  def test_success_type_inherits_from_parent
    parent = build_operation {}
    parent.success(Types::Integer)

    child = Class.new(parent)
    assert_equal Types::Integer, child._success_type
  end

  def test_success_type_child_overrides_parent
    parent = build_operation {}
    parent.success(Types::Integer)

    child = Class.new(parent)
    child.success(Types::String)

    assert_equal Types::String, child._success_type
    assert_equal Types::Integer, parent._success_type
  end

  def test_success_type_nil_when_not_declared
    op = build_operation {}
    assert_nil op._success_type
  end

  # error :codes declaration

  def test_error_codes_stored
    op = build_operation {}
    op.error(:not_found, :invalid)

    assert_equal %i[not_found invalid], op._declared_errors
  end

  def test_error_codes_inherit_from_parent
    parent = build_operation {}
    parent.error(:not_found)

    child = Class.new(parent)
    child.error(:invalid)

    assert_equal %i[not_found invalid], child._declared_errors
    assert_equal %i[not_found], parent._declared_errors
  end

  def test_error_codes_deduplicated_across_inheritance
    parent = build_operation {}
    parent.error(:not_found)

    child = Class.new(parent)
    child.error(:not_found, :invalid)

    assert_equal %i[not_found invalid], child._declared_errors
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
end
