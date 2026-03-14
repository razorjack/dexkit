# frozen_string_literal: true

require "test_helper"

class TestOperationGuards < Minitest::Test
  def setup
    setup_test_database
  end

  # Basic guard behavior

  def test_guard_blocks_and_allows_execution
    op = build_operation do
      prop :blocked, Literal::Types::BooleanType.new
      guard(:denied) { blocked }
      def perform = "ok"
    end

    err = assert_raises(Dex::Error) { op.call(blocked: true) }
    assert_equal :denied, err.code

    assert_equal "ok", op.call(blocked: false)
  end

  def test_guard_message_behavior
    # With explicit message
    op1 = build_operation do
      guard(:denied, "Access denied") { true }
      def perform = "ok"
    end
    err1 = assert_raises(Dex::Error) { op1.new.call }
    assert_equal :denied, err1.code
    assert_equal "Access denied", err1.message

    # Without message uses code as string
    op2 = build_operation do
      guard(:denied) { true }
      def perform = "ok"
    end
    err2 = assert_raises(Dex::Error) { op2.new.call }
    assert_equal "denied", err2.message
  end

  def test_multiple_guards_all_failures_collected
    op = build_operation do
      guard(:first_problem) { true }
      guard(:second_problem) { true }
      def perform = "ok"
    end
    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :first_problem, err.code
    assert_equal 2, err.details.size
    assert_equal :first_problem, err.details[0][:guard]
    assert_equal :second_problem, err.details[1][:guard]
  end

  def test_passing_guard_not_in_failures
    op = build_operation do
      guard(:passes) { false }
      guard(:fails) { true }
      def perform = "ok"
    end
    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :fails, err.code
    assert_equal 1, err.details.size
  end

  def test_guard_block_has_access_to_props
    op = build_operation do
      prop :user_role, String
      guard(:unauthorized) { user_role != "admin" }
      def perform = "ok"
    end
    assert_equal "ok", op.call(user_role: "admin")
    assert_raises(Dex::Error) { op.call(user_role: "guest") }
  end

  # Guard dependencies

  def test_guard_dependency_skips_and_runs
    op = build_operation do
      guard(:missing) { true }
      guard(:invalid, requires: :missing) { true }
      def perform = "ok"
    end

    # Dependent guard skipped when dependency fails
    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal 1, err.details.size
    assert_equal :missing, err.details[0][:guard]

    # Dependent guard runs when dependency passes
    op2 = build_operation do
      guard(:missing) { false }
      guard(:invalid, requires: :missing) { true }
      def perform = "ok"
    end
    err2 = assert_raises(Dex::Error) { op2.new.call }
    assert_equal :invalid, err2.code
  end

  def test_multiple_and_chained_dependencies
    # Multiple dependencies
    op1 = build_operation do
      guard(:missing_a) { true }
      guard(:missing_b) { false }
      guard(:combined, requires: [:missing_a, :missing_b]) { true }
      def perform = "ok"
    end
    err1 = assert_raises(Dex::Error) { op1.new.call }
    assert_equal 1, err1.details.size
    assert_equal :missing_a, err1.details[0][:guard]

    # Chain of dependencies
    op2 = build_operation do
      guard(:level_1) { true }
      guard(:level_2, requires: :level_1) { true }
      def perform = "ok"
    end
    err2 = assert_raises(Dex::Error) { op2.new.call }
    assert_equal 1, err2.details.size
    assert_equal :level_1, err2.details[0][:guard]
  end

  # Guards auto-declare errors

  def test_guard_auto_declares_error_code
    op = build_operation do
      guard(:unauthorized) { false }
      def perform = "ok"
    end
    assert_includes op._declared_errors, :unauthorized
  end

  def test_guard_error_code_usable_in_perform
    op = build_operation do
      guard(:unauthorized) { false }
      def perform = error!(:unauthorized, "runtime check")
    end
    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :unauthorized, err.code
    assert_equal "runtime check", err.message
  end

  # Inheritance

  def test_child_inherits_parent_guards
    parent = build_operation do
      guard(:parent_guard) { true }
      def perform = "ok"
    end
    child = build_operation(parent: parent)
    err = assert_raises(Dex::Error) { child.new.call }
    assert_equal :parent_guard, err.code
  end

  def test_child_can_add_own_guards
    parent = build_operation do
      guard(:parent_guard) { false }
      def perform = "ok"
    end
    child = build_operation(parent: parent) do
      guard(:child_guard) { true }
    end
    err = assert_raises(Dex::Error) { child.new.call }
    assert_equal :child_guard, err.code
  end

  def test_parent_guards_run_first
    parent = build_operation do
      guard(:parent_guard) { true }
      def perform = "ok"
    end
    child = build_operation(parent: parent) do
      guard(:child_guard) { true }
    end
    err = assert_raises(Dex::Error) { child.new.call }
    assert_equal :parent_guard, err.details[0][:guard]
    assert_equal :child_guard, err.details[1][:guard]
  end

  def test_parent_unaffected_by_child_guards
    parent = build_operation do
      def perform = "ok"
    end
    build_operation(parent: parent) do
      guard(:child_guard) { true }
    end
    assert_equal "ok", parent.new.call
  end

  # callable / callable?

  def test_callable
    # Returns Ok when all guards pass
    op1 = build_operation do
      guard(:check) { false }
      def perform = "ok"
    end
    result1 = op1.callable
    assert result1.ok?

    # Returns Err when guard fails
    op2 = build_operation do
      guard(:denied, "Not allowed") { true }
      def perform = "ok"
    end
    result2 = op2.callable
    assert result2.error?
    assert_equal :denied, result2.code
    assert_equal "Not allowed", result2.message

    # Returns all failures in details
    op3 = build_operation do
      guard(:first, "First problem") { true }
      guard(:second, "Second problem") { true }
      def perform = "ok"
    end
    result3 = op3.callable
    assert_equal 2, result3.details.size
    assert_equal :first, result3.details[0][:guard]
    assert_equal :second, result3.details[1][:guard]
  end

  def test_callable_predicate
    # Returns true when callable
    op1 = build_operation do
      guard(:check) { false }
      def perform = "ok"
    end
    assert op1.callable?

    # Returns false when not callable
    op2 = build_operation do
      guard(:check) { true }
      def perform = "ok"
    end
    refute op2.callable?

    # With specific guard
    op3 = build_operation do
      guard(:first) { true }
      guard(:second) { false }
      def perform = "ok"
    end
    refute op3.callable?(:first)
    assert op3.callable?(:second)
  end

  def test_callable_with_props_and_without_guards
    # With props
    op1 = build_operation do
      prop :allowed, Literal::Types::BooleanType.new
      guard(:denied) { !allowed }
      def perform = "ok"
    end
    assert op1.callable?(allowed: true)
    refute op1.callable?(allowed: false)

    # On operation without guards
    op2 = build_operation do
      def perform = "ok"
    end
    assert op2.callable?
    result = op2.callable
    assert result.ok?
  end

  def test_callable_does_not_run_perform_or_callbacks
    performed = false
    called = false

    op = build_operation do
      before { called = true }
      guard(:check) { false }
      define_method(:perform) { performed = true }
    end
    op.callable
    refute performed
    refute called
  end

  def test_callable_bool_with_undeclared_guard_raises
    op = build_operation do
      guard(:check) { true }
      def perform = "ok"
    end
    assert_raises(ArgumentError, /unknown guard :typo/) do
      op.callable?(:typo)
    end
  end

  # Pipeline integration

  def test_guards_run_before_callbacks_and_failure_prevents_them
    log = []
    op = build_operation do
      before { log << :before }
      guard(:check) do
        log << :guard
        false
      end
      def perform = "ok"
    end
    op.new.call
    assert_equal [:guard, :before], log

    log.clear
    op2 = build_operation do
      before { log << :before }
      after { log << :after }
      guard(:check) { true }
      def perform = "ok"
    end
    assert_raises(Dex::Error) { op2.new.call }
    assert_empty log
  end

  def test_guard_failure_and_exception_in_pipeline
    # Guard failure caught by safe
    op1 = build_operation do
      guard(:denied) { true }
      def perform = "ok"
    end
    result = op1.new.safe.call
    assert result.error?
    assert_equal :denied, result.code

    # Guard exception propagates (not caught by rescue_from)
    op2 = build_operation do
      rescue_from RuntimeError, as: :guard_error
      guard(:boom) { raise "guard exploded" }
      def perform = "ok"
    end
    err = assert_raises(RuntimeError) { op2.new.safe.call }
    assert_equal "guard exploded", err.message
  end

  def test_guard_failure_triggers_transaction_rollback
    op = build_operation do
      guard(:denied) { true }
      def perform
        TestModel.create!(name: "should not exist")
      end
    end
    assert_raises(Dex::Error) { op.new.call }
    assert_equal 0, TestModel.count
  end

  # Contract introspection

  def test_contract_includes_guards
    op = build_operation do
      guard(:unauthorized, "Must be admin") { false }
      guard(:already_done, "Already completed", requires: :unauthorized) { false }
      def perform = "ok"
    end
    contract = op.contract
    assert_equal 2, contract.guards.size
    assert_equal :unauthorized, contract.guards[0][:name]
    assert_equal "Must be admin", contract.guards[0][:message]
    assert_equal [], contract.guards[0][:requires]
    assert_equal :already_done, contract.guards[1][:name]
    assert_equal [:unauthorized], contract.guards[1][:requires]
  end

  def test_contract_errors_include_guard_codes
    op = build_operation do
      error :manual_error
      guard(:guard_error) { false }
      def perform = "ok"
    end
    assert_includes op.contract.errors, :manual_error
    assert_includes op.contract.errors, :guard_error
  end

  def test_contract_guards_empty_when_no_guards
    op = build_operation do
      def perform = "ok"
    end
    assert_equal [], op.contract.guards
  end

  # DSL validation

  def test_guard_dsl_validation_basic
    assert_raises(ArgumentError, /must be a Symbol/) do
      build_operation { guard("string_code") { true } }
    end

    assert_raises(ArgumentError, /requires a block/) do
      build_operation { guard(:code) }
    end

    assert_raises(ArgumentError, /duplicate/) do
      build_operation {
        guard(:same) { true }
        guard(:same) { true }
      }
    end
  end

  def test_guard_dsl_validation_requires
    assert_raises(ArgumentError, /no guard with that name/) do
      build_operation { guard(:dependent, requires: :nonexistent) { true } }
    end

    assert_raises(ArgumentError, /must be Symbol/) do
      build_operation {
        guard(:first) { true }
        guard(:second, requires: "first") { true }
      }
    end

    assert_raises(ArgumentError, /no guard with that name/) do
      build_operation {
        guard(:first, requires: :second) { true }
        guard(:second) { true }
      }
    end
  end
end
