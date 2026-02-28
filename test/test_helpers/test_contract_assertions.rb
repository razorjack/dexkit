# frozen_string_literal: true

require "test_helper"
require "dex/test_helpers"

class TestContractAssertions < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  # assert_params — exhaustive name check

  def test_assert_params_passes_with_correct_names
    op = build_operation do
      params do
        attribute :name, Types::String
        attribute :email, Types::String
      end
      def perform = nil
    end
    assert_params(op, :name, :email)
  end

  def test_assert_params_fails_with_missing_name
    op = build_operation do
      params do
        attribute :name, Types::String
        attribute :email, Types::String
      end
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_params(op, :name) }
  end

  def test_assert_params_fails_with_extra_name
    op = build_operation do
      params { attribute :name, Types::String }
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_params(op, :name, :email) }
  end

  # assert_params — with types

  def test_assert_params_with_types
    op = build_operation do
      params do
        attribute :name, Types::String
        attribute :count, Types::Integer
      end
      def perform = nil
    end
    assert_params(op, name: Types::String, count: Types::Integer)
  end

  def test_assert_params_with_wrong_type
    op = build_operation do
      params { attribute :name, Types::String }
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_params(op, name: Types::Integer) }
  end

  # assert_accepts_param

  def test_assert_accepts_param_passes
    op = build_operation do
      params do
        attribute :name, Types::String
        attribute :email, Types::String
      end
      def perform = nil
    end
    assert_accepts_param(op, :name)
  end

  def test_assert_accepts_param_fails_for_missing
    op = build_operation do
      params { attribute :name, Types::String }
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_accepts_param(op, :email) }
  end

  # assert_success_type

  def test_assert_success_type_passes
    op = build_operation do
      success Types::String
      def perform = "hello"
    end
    assert_success_type(op, Types::String)
  end

  def test_assert_success_type_fails_on_mismatch
    op = build_operation do
      success Types::String
      def perform = "hello"
    end
    assert_raises(Minitest::Assertion) { assert_success_type(op, Types::Integer) }
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
      params do
        attribute :name, Types::String
      end
      success Types::String
      error :invalid
      def perform = name
    end
    assert_contract(op, params: [:name], success: Types::String, errors: [:invalid])
  end

  def test_assert_contract_partial_params_only
    op = build_operation do
      params { attribute :x, Types::Integer }
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

class TestContractWithSubject < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  ContractOp = Class.new(Dex::Operation) do
    params do
      attribute :name, Types::String
      attribute :age, Types::Integer
    end
    success Types::String
    error :too_young

    def perform
      error!(:too_young) if age < 18
      "Welcome #{name}"
    end
  end

  testing ContractOp

  def setup
    super
    setup_test_database
  end

  def test_assert_params_uses_subject
    assert_params(:name, :age)
  end

  def test_assert_accepts_param_uses_subject
    assert_accepts_param(:name)
  end

  def test_assert_success_type_uses_subject
    assert_success_type(Types::String)
  end

  def test_assert_error_codes_uses_subject
    assert_error_codes(:too_young)
  end

  def test_assert_contract_uses_subject
    assert_contract(params: [:name, :age], success: Types::String, errors: [:too_young])
  end
end
