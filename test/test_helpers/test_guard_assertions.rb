# frozen_string_literal: true

require "test_helper"
require "dex/test_helpers"

class TestGuardAssertions < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  # assert_callable

  def test_assert_callable_passes_when_all_guards_pass
    op = build_operation do
      guard(:check) { false }
      def perform = "ok"
    end
    assert_callable(op)
  end

  def test_assert_callable_fails_when_guard_fails
    op = build_operation do
      guard(:check) { true }
      def perform = "ok"
    end
    assert_raises(Minitest::Assertion) { assert_callable(op) }
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

  # refute_callable

  def test_refute_callable_passes_when_guard_fails
    op = build_operation do
      guard(:denied) { true }
      def perform = "ok"
    end
    refute_callable(op)
  end

  def test_refute_callable_fails_when_all_guards_pass
    op = build_operation do
      guard(:check) { false }
      def perform = "ok"
    end
    assert_raises(Minitest::Assertion) { refute_callable(op) }
  end

  def test_refute_callable_with_specific_guard
    op = build_operation do
      guard(:first) { true }
      guard(:second) { false }
      def perform = "ok"
    end
    refute_callable(op, :first)
  end

  def test_refute_callable_with_wrong_guard_fails
    op = build_operation do
      guard(:first) { true }
      guard(:second) { false }
      def perform = "ok"
    end
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
