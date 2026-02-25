# frozen_string_literal: true

require "test_helper"

class TestOperationRescue < Minitest::Test
  def setup
    setup_test_database
  end

  # Basic conversion

  def test_converts_exception_to_dex_error
    op = build_operation do
      rescue_from RuntimeError, as: :runtime_failure
      def perform = raise("something broke")
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal :runtime_failure, err.code
  end

  def test_default_message_from_exception
    op = build_operation do
      rescue_from RuntimeError, as: :runtime_failure
      def perform = raise("original message")
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal "original message", err.message
  end

  def test_custom_message_overrides_exception_message
    op = build_operation do
      rescue_from RuntimeError, as: :runtime_failure, message: "custom message"
      def perform = raise("original message")
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal "custom message", err.message
  end

  def test_original_exception_preserved_in_details
    original = RuntimeError.new("boom")
    op = build_operation do
      rescue_from RuntimeError, as: :runtime_failure
      define_method(:perform) { raise original }
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_same original, err.details[:original]
  end

  # Multiple exception classes

  def test_multiple_classes_in_one_call
    op = build_operation do
      rescue_from ArgumentError, TypeError, as: :type_problem
      def perform = raise(ArgumentError, "bad arg")
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal :type_problem, err.code

    op2 = build_operation do
      rescue_from ArgumentError, TypeError, as: :type_problem
      def perform = raise(TypeError, "bad type")
    end
    err2 = assert_raises(Dex::Error) { op2.new.perform }
    assert_equal :type_problem, err2.code
  end

  def test_multiple_declarations
    op = build_operation do
      rescue_from ArgumentError, as: :bad_argument
      rescue_from TypeError, as: :bad_type
      define_method(:perform) { raise ArgumentError }
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal :bad_argument, err.code

    op2 = build_operation do
      rescue_from ArgumentError, as: :bad_argument
      rescue_from TypeError, as: :bad_type
      def perform = raise(TypeError)
    end
    err2 = assert_raises(Dex::Error) { op2.new.perform }
    assert_equal :bad_type, err2.code
  end

  # Passthrough behavior

  def test_dex_error_passes_through_untouched
    op = build_operation do
      rescue_from RuntimeError, as: :runtime_failure
      def perform = error!(:my_error, "explicit failure")
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal :my_error, err.code
    assert_equal "explicit failure", err.message
  end

  def test_unhandled_exception_propagates
    op = build_operation do
      rescue_from ArgumentError, as: :bad_argument
      def perform = raise("unhandled")
    end
    err = assert_raises(RuntimeError) { op.new.perform }
    assert_equal "unhandled", err.message
  end

  # Handler resolution

  def test_later_more_specific_handler_wins
    op = build_operation do
      rescue_from StandardError, as: :general
      rescue_from RuntimeError, as: :specific
      def perform = raise(RuntimeError)
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal :specific, err.code
  end

  def test_subclass_caught_by_general_handler
    op = build_operation do
      rescue_from StandardError, as: :any_standard
      def perform = raise(ArgumentError)
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal :any_standard, err.code
  end

  # Inheritance

  def test_child_inherits_parent_handlers
    parent = build_operation do
      rescue_from ArgumentError, as: :bad_argument
      def perform = raise(ArgumentError)
    end
    child = build_operation(parent: parent)
    err = assert_raises(Dex::Error) { child.new.perform }
    assert_equal :bad_argument, err.code
  end

  def test_child_can_add_own_handlers
    parent = build_operation do
      rescue_from ArgumentError, as: :bad_argument
    end
    child = build_operation(parent: parent) do
      rescue_from TypeError, as: :bad_type
      def perform = raise(TypeError)
    end
    err = assert_raises(Dex::Error) { child.new.perform }
    assert_equal :bad_type, err.code
  end

  def test_parent_unaffected_by_child_handlers
    parent = build_operation do
      rescue_from ArgumentError, as: :bad_argument
      def perform = raise(TypeError)
    end
    child = build_operation(parent: parent) do
      rescue_from TypeError, as: :bad_type
    end
    begin
      child.new.perform
    rescue
      nil
    end
    assert_raises(TypeError) { parent.new.perform }
  end

  # Integration

  def test_safe_returns_err_with_correct_code_and_original
    original = RuntimeError.new("boom")
    op = build_operation do
      rescue_from RuntimeError, as: :runtime_failure
      define_method(:perform) { raise original }
    end
    result = op.new.safe.perform
    assert result.error?
    assert_equal :runtime_failure, result.code
    assert_same original, result.details[:original]
  end

  def test_rescued_error_triggers_transaction_rollback
    op = build_operation do
      rescue_from RuntimeError, as: :runtime_failure
      def perform
        TestModel.create!(name: "should rollback")
        raise RuntimeError
      end
    end
    assert_raises(Dex::Error) { op.new.perform }
    assert_equal 0, TestModel.count
  end

  def test_catches_exceptions_from_before_callback
    op = build_operation do
      rescue_from RuntimeError, as: :callback_failure
      before_perform { raise "before failed" }
      def perform = "ok"
    end
    err = assert_raises(Dex::Error) { op.new.perform }
    assert_equal :callback_failure, err.code
  end

  # Validation

  def test_rescue_from_requires_at_least_one_class
    assert_raises(ArgumentError) do
      build_operation do
        rescue_from as: :some_code
      end
    end
  end
end
