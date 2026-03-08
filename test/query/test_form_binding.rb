# frozen_string_literal: true

require "test_helper"

class TestQueryFormBinding < Minitest::Test
  def setup
    setup_query_database
  end

  def test_model_name_derives_from_class_name
    query_class = define_query(:UserSearch, scope_model: QueryUser)

    assert_equal "user_search", query_class.model_name.param_key
  end

  def test_param_key_override
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      param_key :q
    end

    assert_equal "q", query_class.model_name.param_key
  end

  def test_param_key_rejects_blank
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) do
        param_key ""
      end
    end
    assert_match(/must not be blank/, err.message)
  end

  def test_anonymous_class_falls_back_to_query
    query_class = build_query(scope_model: QueryUser)

    assert_equal "query", query_class.model_name.param_key
  end

  def test_persisted_returns_false
    query_class = build_query(scope_model: QueryUser)

    query = query_class.new
    refute query.persisted?
  end

  def test_to_params_returns_non_nil_props_and_sort
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
      sort :name
    end

    query = query_class.new(role: "admin", sort: "-name")
    params = query.to_params
    assert_equal "admin", params[:role]
    assert_equal "-name", params[:sort]
    refute params.key?(:status)
  end

  def test_to_params_without_sort
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    query = query_class.new(role: "admin")
    params = query.to_params
    assert_equal "admin", params[:role]
    refute params.key?(:sort)
  end

  def test_to_params_includes_default_sort
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "-name"
    end

    query = query_class.new
    params = query.to_params
    assert_equal "-name", params[:sort]
  end

  def test_prop_readers_work_on_instance
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
    end

    query = query_class.new(role: "admin", status: "active")
    assert_equal "admin", query.role
    assert_equal "active", query.status
  end
end
