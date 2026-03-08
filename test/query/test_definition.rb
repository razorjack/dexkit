# frozen_string_literal: true

require "test_helper"

class TestQueryDefinition < Minitest::Test
  def setup
    setup_query_database
  end

  def test_scope_declaration
    query_class = build_query(scope_model: QueryUser)

    assert query_class._scope_block
  end

  def test_scope_requires_block
    assert_raises(ArgumentError) do
      build_query do
        scope
      end
    end
  end

  def test_reserved_prop_names_rejected
    %i[scope sort resolve call from_params to_params param_key].each do |name|
      assert_raises(ArgumentError, "Expected :#{name} to be rejected") do
        build_query(scope_model: QueryUser) do
          prop name, String
        end
      end
    end
  end

  def test_filter_requires_declared_prop
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        filter :name
      end
    end
    assert_match(/requires a prop/, err.message)
  end

  def test_filter_rejects_unknown_strategy
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        prop? :name, String
        filter :name, :fuzzy
      end
    end
    assert_match(/Unknown filter strategy/, err.message)
  end

  def test_filter_rejects_duplicate
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        prop? :name, String
        filter :name
        filter :name
      end
    end
    assert_match(/already declared/, err.message)
  end

  def test_block_filter_requires_single_name
    query_class = build_query(scope_model: QueryUser) do
      prop? :name, String
      filter(:name) { |scope, _value| scope }
    end

    assert query_class._filter_registry.key?(:name)
  end

  def test_sort_rejects_duplicate
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        sort :name
        sort :name
      end
    end
    assert_match(/already declared/, err.message)
  end

  def test_sort_default_references_declared_sort
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        sort :name, default: "-created_at"
      end
    end
    assert_match(/unknown sort/, err.message)
  end

  def test_multiple_defaults_rejected
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        sort :name, default: "name"
        sort :email, default: "email"
      end
    end
    assert_match(/already set/, err.message)
  end

  def test_filters_introspection
    query_class = build_query(scope_model: QueryUser) do
      prop? :name, String
      prop? :role, String
      filter :name, :contains
      filter :role
    end

    assert_equal %i[name role], query_class.filters
  end

  def test_sorts_introspection
    query_class = build_query(scope_model: QueryUser) do
      sort :name, :created_at
    end

    assert_equal %i[name created_at], query_class.sorts
  end
end
