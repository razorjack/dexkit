# frozen_string_literal: true

require "test_helper"

class TestQuerySorting < Minitest::Test
  def setup
    setup_query_database
    seed_query_users(
      { name: "Charlie", email: "charlie@example.com", role: "user", age: 35, status: "active" },
      { name: "Alice", email: "alice@example.com", role: "admin", age: 30, status: "active" },
      { name: "Bob", email: "bob@example.com", role: "user", age: 25, status: "inactive" }
    )
  end

  def test_ascending_sort
    query_class = build_query(scope_model: QueryUser) do
      sort :name
    end

    result = query_class.call(sort: "name")
    assert_equal %w[Alice Bob Charlie], result.map(&:name)
  end

  def test_descending_sort
    query_class = build_query(scope_model: QueryUser) do
      sort :name
    end

    result = query_class.call(sort: "-name")
    assert_equal %w[Charlie Bob Alice], result.map(&:name)
  end

  def test_default_sort
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
    end

    result = query_class.call
    assert_equal %w[Alice Bob Charlie], result.map(&:name)
  end

  def test_default_sort_descending
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "-name"
    end

    result = query_class.call
    assert_equal %w[Charlie Bob Alice], result.map(&:name)
  end

  def test_custom_sort_block
    query_class = build_query(scope_model: QueryUser) do
      sort(:newest) { |scope| scope.order(created_at: :desc) }
    end

    result = query_class.call(sort: "newest")
    assert_equal "Bob", result.first.name
  end

  def test_custom_sort_rejects_dash_prefix
    query_class = build_query(scope_model: QueryUser) do
      sort(:newest) { |scope| scope.order(created_at: :desc) }
    end

    err = assert_raises(ArgumentError) do
      query_class.call(sort: "-newest")
    end
    assert_match(/Custom sorts cannot/, err.message)
  end

  def test_unknown_sort_raises
    query_class = build_query(scope_model: QueryUser) do
      sort :name
    end

    err = assert_raises(ArgumentError) do
      query_class.call(sort: "email")
    end
    assert_match(/Unknown sort/, err.message)
  end

  def test_no_sort_no_order
    query_class = build_query(scope_model: QueryUser) do
      sort :name
    end

    result = query_class.call
    assert_equal 3, result.count
  end

  def test_multiple_column_sorts
    query_class = build_query(scope_model: QueryUser) do
      sort :name, :age, :created_at
    end

    result = query_class.call(sort: "age")
    assert_equal %w[Bob Alice Charlie], result.map(&:name)
  end

  def test_custom_sort_default
    query_class = build_query(scope_model: QueryUser) do
      sort(:newest, default: "newest") { |scope| scope.order(created_at: :desc) }
    end

    result = query_class.call
    assert_equal "Bob", result.first.name
  end

  def test_sort_reader_returns_current_sort
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "-name"
    end

    query = query_class.new(sort: "name")
    assert_equal "name", query.sort

    query_default = query_class.new
    assert_equal "-name", query_default.sort
  end
end
