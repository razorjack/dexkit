# frozen_string_literal: true

require "test_helper"

class TestQueryInheritance < Minitest::Test
  def setup
    setup_query_database
    seed_query_users
  end

  def test_subclass_inherits_filters
    parent = define_query(:BaseUserQuery, scope_model: QueryUser) do
      prop? :role, String
      filter :role
      sort :name
    end

    child = define_query(:ExtendedUserQuery, parent: parent) do
      prop? :status, String
      filter :status
    end

    result = child.call(role: "user", status: "active")
    assert_equal 1, result.count
    assert_equal "Bob", result.first.name
  end

  def test_subclass_inherits_sorts
    parent = define_query(:BaseUserQuery, scope_model: QueryUser) do
      sort :name, :age
    end

    child = define_query(:ExtendedUserQuery, parent: parent) do
      sort :email
    end

    assert_includes child.sorts, :name
    assert_includes child.sorts, :age
    assert_includes child.sorts, :email
  end

  def test_subclass_inherits_props
    parent = define_query(:BaseUserQuery, scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    child = define_query(:ExtendedUserQuery, parent: parent) do
      prop? :status, String
      filter :status
    end

    query = child.new(role: "admin", status: "active")
    assert_equal "admin", query.role
    assert_equal "active", query.status
  end

  def test_scope_replaces_in_subclass
    parent = define_query(:BaseUserQuery) do
      scope { QueryUser.where(status: "active") }
    end

    child = define_query(:ExtendedUserQuery, parent: parent) do
      scope { QueryUser.where(status: "inactive") }
    end

    assert_equal 2, parent.call.count
    assert_equal 1, child.call.count
  end

  def test_subclass_inherits_default_sort
    parent = define_query(:BaseUserQuery, scope_model: QueryUser) do
      sort :name, default: "name"
    end

    child = define_query(:ExtendedUserQuery, parent: parent) do
      sort :age
    end

    result = child.call
    assert_equal %w[Alice Bob Charlie], result.map(&:name)
  end

  def test_parent_unchanged_by_subclass
    parent = define_query(:BaseUserQuery, scope_model: QueryUser) do
      prop? :role, String
      filter :role
      sort :name
    end

    define_query(:ExtendedUserQuery, parent: parent) do
      prop? :status, String
      filter :status
      sort :email
    end

    assert_equal [:role], parent.filters
    assert_equal [:name], parent.sorts
  end
end
