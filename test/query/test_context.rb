# frozen_string_literal: true

require "test_helper"

class TestQueryContext < Minitest::Test
  def setup
    setup_query_database
    seed_query_users
  end

  # Basic context resolution

  def test_context_fills_prop_from_ambient
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context :role
    end

    result = Dex.with_context(role: "admin") { query_class.call }
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_explicit_kwarg_wins_over_context
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context :role
    end

    result = Dex.with_context(role: "admin") { query_class.call(role: "user") }
    assert_equal 2, result.count
  end

  def test_works_without_ambient_context
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context :role
    end

    result = query_class.call
    assert_equal 3, result.count
  end

  # Identity shorthand

  def test_identity_shorthand
    query_class = build_query(scope_model: QueryUser) do
      prop? :status, String
      filter :status
      context :status
    end

    result = Dex.with_context(status: "active") { query_class.call }
    assert_equal 2, result.count
  end

  # Explicit mapping

  def test_explicit_mapping
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context role: :current_role
    end

    result = Dex.with_context(current_role: "admin") { query_class.call }
    assert_equal 1, result.count
  end

  # Mixed forms

  def test_mixed_shorthand_and_mapping
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
      context :status, role: :current_role
    end

    result = Dex.with_context(current_role: "user", status: "active") { query_class.call }
    assert_equal 1, result.count
    assert_equal "Bob", result.first.name
  end

  # Introspection

  def test_context_mappings
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      context :status, role: :current_role
    end

    assert_equal({ status: :status, role: :current_role }, query_class.context_mappings)
  end

  def test_context_mappings_empty_by_default
    query_class = build_query(scope_model: QueryUser)
    assert_equal({}, query_class.context_mappings)
  end

  # Inheritance

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

  def test_child_extends_parent_context
    parent = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context :role
    end

    child = build_query(parent: parent) do
      prop? :status, String
      filter :status
      context status: :current_status
    end

    result = Dex.with_context(role: "user", current_status: "active") { child.call }
    assert_equal 1, result.count
  end

  def test_parent_unaffected_by_child_context
    parent = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context :role
    end

    build_query(parent: parent) do
      prop? :status, String
      context status: :current_status
    end

    assert_equal({ role: :role }, parent.context_mappings)
  end

  # DSL validation

  def test_context_referencing_undeclared_prop_raises
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        context role: :current_role
      end
    end
    assert_match(/undeclared prop/, err.message)
  end

  def test_context_shorthand_must_be_symbol
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        prop? :role, String
        context "role"
      end
    end
    assert_match(/must be a Symbol/, err.message)
  end

  def test_context_with_no_arguments_raises
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) { context }
    end
    assert_match(/requires at least one/, err.message)
  end

  def test_context_mapping_value_must_be_symbol
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        prop? :role, String
        context role: "current_role"
      end
    end
    assert_match(/context key must be a Symbol/, err.message)
  end
end
