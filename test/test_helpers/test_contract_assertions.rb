# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestContractAssertions < Minitest::Test
  include Dex::Operation::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  # assert_params — exhaustive name check

  def test_assert_params_passes_with_correct_names
    op = build_operation do
      prop :name, String
      prop :email, String
      def perform = nil
    end
    assert_params(op, :name, :email)
  end

  def test_assert_params_fails_with_missing_name
    op = build_operation do
      prop :name, String
      prop :email, String
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_params(op, :name) }
  end

  def test_assert_params_fails_with_extra_name
    op = build_operation do
      prop :name, String
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_params(op, :name, :email) }
  end

  # assert_params — with types

  def test_assert_params_with_types
    op = build_operation do
      prop :name, String
      prop :count, Integer
      def perform = nil
    end
    assert_params(op, name: String, count: Integer)
  end

  def test_assert_params_with_wrong_type
    op = build_operation do
      prop :name, String
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_params(op, name: Integer) }
  end

  # assert_accepts_param

  def test_assert_accepts_param_passes
    op = build_operation do
      prop :name, String
      prop :email, String
      def perform = nil
    end
    assert_accepts_param(op, :name)
  end

  def test_assert_accepts_param_fails_for_missing
    op = build_operation do
      prop :name, String
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_accepts_param(op, :email) }
  end

  # assert_success_type

  def test_assert_success_type_passes
    op = build_operation do
      success String
      def perform = "hello"
    end
    assert_success_type(op, String)
  end

  def test_assert_success_type_fails_on_mismatch
    op = build_operation do
      success String
      def perform = "hello"
    end
    assert_raises(Minitest::Assertion) { assert_success_type(op, Integer) }
  end

  # assert_error_codes

  def test_assert_error_codes_passes
    op = build_operation do
      error :not_found, :invalid
      def perform = nil
    end
    assert_error_codes(op, :not_found, :invalid)
  end

  def test_assert_error_codes_order_independent
    op = build_operation do
      error :not_found, :invalid
      def perform = nil
    end
    assert_error_codes(op, :invalid, :not_found)
  end

  def test_assert_error_codes_fails_on_mismatch
    op = build_operation do
      error :not_found
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_error_codes(op, :not_found, :invalid) }
  end

  # assert_contract

  def test_assert_contract_full
    op = build_operation do
      prop :name, String
      success String
      error :invalid
      def perform = name
    end
    assert_contract(op, params: [:name], success: String, errors: [:invalid])
  end

  def test_assert_contract_partial_params_only
    op = build_operation do
      prop :x, Integer
      def perform = x
    end
    assert_contract(op, params: [:x])
  end

  def test_assert_contract_errors_only
    op = build_operation do
      error :boom
      def perform = nil
    end
    assert_contract(op, errors: [:boom])
  end
end
