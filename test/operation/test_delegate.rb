# frozen_string_literal: true

require "test_helper"

class TestOperationDelegate < Minitest::Test
  def setup
    setup_test_database
  end

  def test_default_delegates_all_attributes
    op = operation(params: { name: Types::String, count: Types::Integer }) do
      "#{name}-#{count}"
    end

    assert_equal "test-3", op.new(name: "test", count: 3).call
  end

  def test_params_accessor_still_works_alongside_delegation
    op = operation(params: { name: Types::String }) do
      [name, params.name]
    end

    assert_equal ["hello", "hello"], op.new(name: "hello").call
  end

  def test_delegate_false_disables_delegation
    op = build_operation do
      params(delegate: false) { attribute :name, Types::String }
      def perform = respond_to?(:name)
    end

    refute op.new(name: "test").call
  end

  def test_delegate_true_explicit
    op = build_operation do
      params(delegate: true) { attribute :name, Types::String }
      def perform = name
    end

    assert_equal "explicit", op.new(name: "explicit").call
  end

  def test_delegate_symbol_delegates_only_that_attribute
    op = build_operation do
      params(delegate: :name) do
        attribute :name, Types::String
        attribute :email, Types::String
      end
      def perform = [name, respond_to?(:email)]
    end

    assert_equal ["Alice", false], op.new(name: "Alice", email: "a@x.com").call
  end

  def test_delegate_array_delegates_listed_attributes
    op = build_operation do
      params(delegate: [:name, :email]) do
        attribute :name, Types::String
        attribute :email, Types::String
        attribute :age, Types::Integer
      end
      def perform = [name, email, respond_to?(:age)]
    end

    assert_equal ["Bob", "b@x.com", false], op.new(name: "Bob", email: "b@x.com", age: 30).call
  end

  def test_delegated_methods_available_in_callbacks
    log = []
    op = build_operation do
      params { attribute :name, Types::String }
      before { log << name }
      def perform = "done"
    end

    op.new(name: "Alice").call
    assert_equal ["Alice"], log
  end

  def test_child_inherits_delegated_methods
    parent = build_operation do
      params { attribute :name, Types::String }
      def perform = name
    end
    child = build_operation(parent: parent)

    assert_equal "inherited", child.new(name: "inherited").call
  end
end
