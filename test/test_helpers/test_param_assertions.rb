# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestParamAssertions < Minitest::Test
  include Dex::Operation::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_assert_invalid_params
    op = build_operation do
      prop :name, String
      def perform = nil
    end
    assert_invalid_params(op, name: 123)
    assert_raises(Minitest::Assertion) { assert_invalid_params(op, name: "Alice") }
  end

  def test_assert_valid_params
    op = build_operation do
      prop :name, String
      def perform = nil
    end
    assert_valid_params(op, name: "Alice")
    assert_raises(Literal::TypeError) { assert_valid_params(op, name: 123) }
  end
end
