# frozen_string_literal: true

require "test_helper"
require "dex/test_helpers"

class TestParamAssertions < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_assert_invalid_params_passes
    op = build_operation do
      params { attribute :name, Types::Strict::String }
      def perform = nil
    end
    assert_invalid_params(op, name: 123)
  end

  def test_assert_invalid_params_fails_for_valid
    op = build_operation do
      params { attribute :name, Types::Strict::String }
      def perform = nil
    end
    assert_raises(Minitest::Assertion) { assert_invalid_params(op, name: "Alice") }
  end

  def test_assert_valid_params_passes
    op = build_operation do
      params { attribute :name, Types::String }
      def perform = nil
    end
    assert_valid_params(op, name: "Alice")
  end

  def test_assert_valid_params_fails_for_invalid
    op = build_operation do
      params { attribute :name, Types::Strict::String }
      def perform = nil
    end
    assert_raises(Dry::Struct::Error) { assert_valid_params(op, name: 123) }
  end
end

class TestParamAssertionsWithSubject < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  ParamOp = Class.new(Dex::Operation) do
    params { attribute :count, Types::Strict::Integer }
    def perform = count
  end

  testing ParamOp

  def setup
    super
    setup_test_database
  end

  def test_assert_invalid_params_uses_subject
    assert_invalid_params(count: "not a number")
  end

  def test_assert_valid_params_uses_subject
    assert_valid_params(count: 5)
  end
end
