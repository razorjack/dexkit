# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestGuardAssertions < Minitest::Test
  include Dex::Operation::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_assert_callable
    passing_op = build_operation do
      guard(:check) { false }
      def perform = "ok"
    end
    assert_callable(passing_op)

    failing_op = build_operation do
      guard(:check) { true }
      def perform = "ok"
    end
    assert_raises(Minitest::Assertion) { assert_callable(failing_op) }
  end

  def test_assert_callable_with_params
    op = build_operation do
      prop :allowed, Literal::Types::BooleanType.new
      guard(:denied) { !allowed }
      def perform = "ok"
    end
    assert_callable(op, allowed: true)
  end

  def test_assert_callable_passes_without_guards
    op = build_operation do
      def perform = "ok"
    end
    assert_callable(op)
  end

  def test_refute_callable
    failing_op = build_operation do
      guard(:denied) { true }
      def perform = "ok"
    end
    refute_callable(failing_op)

    passing_op = build_operation do
      guard(:check) { false }
      def perform = "ok"
    end
    assert_raises(Minitest::Assertion) { refute_callable(passing_op) }
  end

  def test_refute_callable_with_specific_guard
    op = build_operation do
      guard(:first) { true }
      guard(:second) { false }
      def perform = "ok"
    end
    refute_callable(op, :first)
    assert_raises(Minitest::Assertion) { refute_callable(op, :second) }
  end

  def test_refute_callable_with_params
    op = build_operation do
      prop :allowed, Literal::Types::BooleanType.new
      guard(:denied) { !allowed }
      def perform = "ok"
    end
    refute_callable(op, :denied, allowed: false)
  end
end
