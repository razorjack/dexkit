# frozen_string_literal: true

require "test_helper"

class TestOperationResult < Minitest::Test
  def setup
    setup_test_database
  end

  def test_result_schema_definition
    op = Class.new(Dex::Operation) do
      result do
        attribute :id, Types::Integer
        attribute :name, Types::String
      end

      def perform
        {id: 1, name: "Test"}
      end
    end

    result = op.new.perform
    assert_instance_of op::Result, result
    assert_equal 1, result.id
    assert_equal "Test", result.name
  end

  def test_result_wraps_hash_only
    op = Class.new(Dex::Operation) do
      result do
        attribute :value, Types::String
      end

      def perform
        "raw string"
      end
    end

    result = op.new.perform
    assert_equal "raw string", result
  end

  def test_result_without_schema
    op = Class.new(Dex::Operation) do
      def perform
        {id: 1, name: "Test"}
      end
    end

    result = op.new.perform
    assert_instance_of Hash, result
    assert_equal 1, result[:id]
    assert_equal "Test", result[:name]
  end

  def test_result_with_nested_attributes
    op = Class.new(Dex::Operation) do
      result do
        attribute :user, Types::Hash
        attribute :status, Types::String
      end

      def perform
        {user: {name: "John"}, status: "active"}
      end
    end

    result = op.new.perform
    assert_equal({name: "John"}, result.user)
    assert_equal "active", result.status
  end
end
