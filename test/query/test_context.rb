# frozen_string_literal: true

require "test_helper"

class TestQueryContext < Minitest::Test
  def setup
    setup_query_database
    seed_query_users
  end

  def test_ambient_fills_prop_and_explicit_wins
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context :role
    end

    result = Dex.with_context(role: "admin") { query_class.call }
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name

    result = Dex.with_context(role: "admin") { query_class.call(role: "user") }
    assert_equal 2, result.count
  end

  def test_child_inherits_parent_context
    parent = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context :role
    end

    child = build_query(parent: parent) do
      prop? :status, String
      filter :status
    end

    result = Dex.with_context(role: "user") { child.call(status: "active") }
    assert_equal 1, result.count
    assert_equal "Bob", result.first.name
  end

  def test_context_referencing_undeclared_prop_raises
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        context role: :current_role
      end
    end
    assert_match(/undeclared prop/, err.message)
  end
end
