# frozen_string_literal: true

require "test_helper"

class TestQueryFilters < Minitest::Test
  def setup
    setup_query_database
    QueryUser.create!(name: "Alice", email: "alice@example.com", role: "admin", age: 30, status: "active")
    QueryUser.create!(name: "Bob", email: "bob@example.com", role: "user", age: 25, status: "active")
    QueryUser.create!(name: "Charlie", email: "charlie@example.com", role: "user", age: 35, status: "inactive")
  end

  def test_eq_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, String
      filter :role
    end

    result = query_class.call(role: "admin")
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_not_eq_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, String
      filter :role, :not_eq
    end

    result = query_class.call(role: "admin")
    assert_equal 2, result.count
  end

  def test_contains_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :name, String
      filter :name, :contains
    end

    result = query_class.call(name: "li")
    assert_equal 2, result.count # Alice, Charlie
  end

  def test_starts_with_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :name, String
      filter :name, :starts_with
    end

    result = query_class.call(name: "Al")
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_ends_with_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :name, String
      filter :name, :ends_with
    end

    result = query_class.call(name: "ob")
    assert_equal 1, result.count
    assert_equal "Bob", result.first.name
  end

  def test_gt_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :age, Integer
      filter :age, :gt
    end

    result = query_class.call(age: 29)
    assert_equal 2, result.count # Alice (30), Charlie (35)
  end

  def test_gte_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :age, Integer
      filter :age, :gte
    end

    result = query_class.call(age: 30)
    assert_equal 2, result.count # Alice (30), Charlie (35)
  end

  def test_lt_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :age, Integer
      filter :age, :lt
    end

    result = query_class.call(age: 30)
    assert_equal 1, result.count
    assert_equal "Bob", result.first.name
  end

  def test_lte_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :age, Integer
      filter :age, :lte
    end

    result = query_class.call(age: 30)
    assert_equal 2, result.count # Bob (25), Alice (30)
  end

  def test_in_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, _Array(String)
      filter :role, :in
    end

    result = query_class.call(role: %w[admin user])
    assert_equal 3, result.count
  end

  def test_not_in_strategy
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, _Array(String)
      filter :role, :not_in
    end

    result = query_class.call(role: %w[admin])
    assert_equal 2, result.count
  end

  def test_custom_filter_block
    query_class = build_query do
      scope { QueryUser.all }
      prop? :search, String
      filter(:search) do |scope, value|
        sanitized = ActiveRecord::Base.sanitize_sql_like(value)
        scope.where("name LIKE ? OR email LIKE ?", "%#{sanitized}%", "%#{sanitized}%")
      end
    end

    result = query_class.call(search: "alice")
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_nil_skip_for_optional_prop
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, String
      filter :role
    end

    result = query_class.call
    assert_equal 3, result.count
  end

  def test_nil_skip_for_optional_block_filter
    query_class = build_query do
      scope { QueryUser.all }
      prop? :search, String
      filter(:search) { |scope, _value| scope.where(role: "admin") }
    end

    result = query_class.call
    assert_equal 3, result.count
  end

  def test_custom_filter_block_returning_nil_preserves_scope
    query_class = build_query do
      scope { QueryUser.all }
      prop? :search, String
      prop? :role, String
      filter(:search) { |scope, value| scope.where("name LIKE ?", "%#{value}%") if value.present? }
      filter :role
    end

    result = query_class.call(search: "", role: "admin")
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_in_skip_on_nil
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, _Array(String)
      filter :role, :in
    end

    result = query_class.call
    assert_equal 3, result.count
  end

  def test_in_skip_on_empty_array
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, _Array(String)
      filter :role, :in
    end

    result = query_class.call(role: [])
    assert_equal 3, result.count
  end

  def test_not_in_skip_on_empty_array
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, _Array(String)
      filter :role, :not_in
    end

    result = query_class.call(role: [])
    assert_equal 3, result.count
  end

  def test_column_mapping
    query_class = build_query do
      scope { QueryUser.all }
      prop? :user_role, String
      filter :user_role, :eq, column: :role
    end

    result = query_class.call(user_role: "admin")
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_like_wildcards_are_sanitized
    QueryUser.create!(name: "Test%User", email: "test@example.com", role: "user", age: 20, status: "active")

    query_class = build_query do
      scope { QueryUser.all }
      prop? :name, String
      filter :name, :contains
    end

    result = query_class.call(name: "%")
    assert_equal 1, result.count
    assert_equal "Test%User", result.first.name
  end

  def test_interleaved_optional_prop_and_filter_declarations
    query_class = build_query do
      scope { QueryUser.all }
      prop? :role, String
      filter :role
      prop? :status, String
      filter :status
    end

    result = query_class.call(role: "admin")
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end
end
