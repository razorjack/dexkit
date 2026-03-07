# frozen_string_literal: true

require "test_helper"

class TestOperationInheritance < Minitest::Test
  def setup
    setup_test_database
  end

  # --- Wrappers apply at each inheritance level ---

  def test_child_operation_is_wrapped
    op = build_operation(parent: build_operation) do
      rescue_from RuntimeError, as: :runtime_error
      def perform = raise(RuntimeError)
    end
    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :runtime_error, err.code
  end

  def test_call_is_public
    op = build_operation { def perform = "ok" }
    assert_equal "ok", op.new.call
  end

  # --- Each wrapper appears once regardless of depth ---

  def test_wrappers_appear_once_in_child_ancestors
    parent = build_operation
    child = build_operation(parent: parent)

    wrapper_modules = [
      Dex::CallbackWrapper, Dex::RescueWrapper, Dex::RecordWrapper,
      Dex::TransactionWrapper, Dex::LockWrapper, Dex::ResultWrapper
    ]

    wrapper_modules.each do |mod|
      count = child.ancestors.count(mod)
      assert_equal 1, count, "#{mod} appears #{count} times in child, expected 1"
    end
  end

  def test_wrappers_appear_once_in_grandchild_ancestors
    parent = build_operation
    child = build_operation(parent: parent)
    grandchild = build_operation(parent: child)

    wrapper_modules = [
      Dex::CallbackWrapper, Dex::RescueWrapper, Dex::RecordWrapper,
      Dex::TransactionWrapper, Dex::LockWrapper, Dex::ResultWrapper
    ]

    wrapper_modules.each do |mod|
      count = grandchild.ancestors.count(mod)
      assert_equal 1, count, "#{mod} appears #{count} times in grandchild, expected 1"
    end
  end

  # --- Callbacks run once ---

  def test_callbacks_run_once_in_child
    log = []
    parent = build_operation do
      before { log << :callback }
      def perform = nil
    end
    child = build_operation(parent: parent)
    child.new.call
    assert_equal 1, log.count(:callback), "callback should run exactly once"
  end

  def test_callbacks_run_once_in_grandchild
    log = []
    grandparent = build_operation do
      before { log << :callback }
      def perform = nil
    end
    parent = build_operation(parent: grandparent)
    child = build_operation(parent: parent)
    child.new.call
    assert_equal 1, log.count(:callback), "callback should run exactly once in grandchild"
  end

  # --- Recording creates exactly 1 record ---

  def test_recording_creates_one_record_for_child
    with_recording do
      parent = define_operation(:InheritRecordParent) do
        prop :name, String
        def perform = name
      end
      child = define_operation(:InheritRecordChild, parent: parent) do
        def perform = "child: #{name}"
      end

      child.new(name: "test").call

      assert_equal 1, OperationRecord.count
    end
  end

  def test_recording_creates_one_record_for_grandchild
    with_recording do
      grandparent = define_operation(:InheritRecordGrandparent) do
        prop :name, String
        def perform = name
      end
      parent = define_operation(:InheritRecordParent2, parent: grandparent)
      child = define_operation(:InheritRecordGrandchild, parent: parent) do
        def perform = "grandchild: #{name}"
      end

      child.new(name: "test").call

      assert_equal 1, OperationRecord.count
      assert_equal "InheritRecordGrandchild", OperationRecord.last.name
    end
  end

  # --- rescue_from converts once ---

  def test_rescue_from_converts_once_in_child
    parent = build_operation do
      rescue_from ArgumentError, as: :bad_arg
      def perform = raise(ArgumentError, "oops")
    end
    child = build_operation(parent: parent)

    err = assert_raises(Dex::Error) { child.new.call }
    assert_equal :bad_arg, err.code
    assert_instance_of ArgumentError, err.details[:original]
  end

  def test_rescue_from_converts_once_in_grandchild
    grandparent = build_operation do
      rescue_from ArgumentError, as: :bad_arg
      def perform = raise(ArgumentError, "oops")
    end
    parent = build_operation(parent: grandparent)
    child = build_operation(parent: parent)

    err = assert_raises(Dex::Error) { child.new.call }
    assert_equal :bad_arg, err.code
  end

  # --- ResultWrapper catches halt once ---

  def test_result_wrapper_catches_error_once_in_child
    parent = build_operation do
      error :not_found
      def perform = error!(:not_found, "gone")
    end
    child = build_operation(parent: parent)

    err = assert_raises(Dex::Error) { child.new.call }
    assert_equal :not_found, err.code
  end

  def test_result_wrapper_returns_success_once_in_grandchild
    grandparent = build_operation do
      def perform = success!(42)
    end
    parent = build_operation(parent: grandparent)
    child = build_operation(parent: parent)

    assert_equal 42, child.new.call
  end

  # --- 3-level grandchild integration test ---

  def test_grandchild_integration_all_wrappers
    log = []
    with_recording do
      grandparent = define_operation(:IntegrationGrandparent) do
        prop :name, String
        rescue_from ArgumentError, as: :bad_arg
        before { log << :before }
        after { log << :after }

        def perform
          "Hello #{name}"
        end
      end

      parent = define_operation(:IntegrationParent, parent: grandparent)

      child = define_operation(:IntegrationGrandchild, parent: parent) do
        def perform
          "Override: #{name}"
        end
      end

      result = child.new(name: "world").call

      assert_equal "Override: world", result
      assert_equal [:before, :after], log
      assert_equal 1, OperationRecord.count
      assert_equal "IntegrationGrandchild", OperationRecord.last.name
    end
  end

  def test_grandchild_integration_error_flow
    with_recording do
      grandparent = define_operation(:ErrorFlowGrandparent) do
        prop :name, String
        error :not_found

        def perform
          error!(:not_found, "missing")
        end
      end

      parent = define_operation(:ErrorFlowParent, parent: grandparent)
      child = define_operation(:ErrorFlowGrandchild, parent: parent)

      err = assert_raises(Dex::Error) { child.new(name: "test").call }

      assert_equal :not_found, err.code
      assert_equal 1, OperationRecord.count, "error! should record with error status"
      assert_equal "error", OperationRecord.last.status
    end
  end

  def test_grandchild_safe_execution
    grandparent = build_operation do
      def perform = error!(:broken)
    end
    parent = build_operation(parent: grandparent)
    child = build_operation(parent: parent)

    result = child.new.safe.call

    assert result.error?
    assert_equal :broken, result.code
  end
end
