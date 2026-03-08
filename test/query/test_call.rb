# frozen_string_literal: true

require "test_helper"

class TestQueryCall < Minitest::Test
  def setup
    setup_query_database
    seed_query_users
  end

  def test_call_returns_relation
    query_class = build_query(scope_model: QueryUser)

    result = query_class.call
    assert_kind_of ActiveRecord::Relation, result
    assert_equal 3, result.count
  end

  def test_count_shortcut
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    assert_equal 2, query_class.count(role: "user")
  end

  def test_exists_shortcut
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    assert query_class.exists?(role: "admin")
    refute query_class.exists?(role: "guest")
  end

  def test_any_shortcut
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    assert query_class.any?(role: "admin")
    refute query_class.any?(role: "guest")
  end

  def test_scope_injection
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    injected = QueryUser.where(status: "active")
    result = query_class.call(scope: injected, role: "user")
    assert_equal 1, result.count
    assert_equal "Bob", result.first.name
  end

  def test_scope_injection_validates_model
    query_class = build_query(scope_model: QueryUser)

    err = assert_raises(ArgumentError) do
      # Pass a non-relation to trigger validation
      query_class.call(scope: "not a scope")
    end
    assert_match(/Injected scope must be a queryable scope/, err.message)
  end

  def test_scope_evaluated_per_call_with_props
    query_class = build_query do
      scope { QueryUser.where(role: role) }
      prop :role, String
    end

    result = query_class.call(role: "admin")
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name

    result2 = query_class.call(role: "user")
    assert_equal 2, result2.count
  end

  def test_resolve_on_instance
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    query = query_class.new(role: "admin")
    result = query.resolve
    assert_equal 1, result.count
  end

  def test_no_scope_raises
    query_class = build_query {}

    err = assert_raises(ArgumentError) do
      query_class.call
    end
    assert_match(/No scope defined/, err.message)
  end

  def test_filters_and_sort_combined
    query_class = build_query(scope_model: QueryUser) do
      prop? :status, String
      filter :status
      sort :name
    end

    result = query_class.call(status: "active", sort: "-name")
    assert_equal %w[Bob Alice], result.map(&:name)
  end
end
