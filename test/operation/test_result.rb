# frozen_string_literal: true

require "test_helper"

class TestOperationResult < Minitest::Test
  def setup
    setup_test_database
  end

  def test_result_schema_definition
    op = operation(result: {id: Types::Integer, name: Types::String}) do
      {id: 1, name: "Test"}
    end

    result = op.new.perform
    assert_instance_of op::Result, result
    assert_equal 1, result.id
    assert_equal "Test", result.name
  end

  def test_result_wraps_hash_only
    op = operation(result: {value: Types::String}) do
      "raw string"
    end

    result = op.new.perform
    assert_equal "raw string", result
  end

  def test_result_without_schema
    op = operation do
      {id: 1, name: "Test"}
    end

    result = op.new.perform
    assert_instance_of Hash, result
    assert_equal 1, result[:id]
    assert_equal "Test", result[:name]
  end

  def test_result_with_nested_attributes
    op = operation(result: {user: Types::Hash, status: Types::String}) do
      {user: {name: "John"}, status: "active"}
    end

    result = op.new.perform
    assert_equal({name: "John"}, result.user)
    assert_equal "active", result.status
  end
end
