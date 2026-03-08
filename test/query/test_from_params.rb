# frozen_string_literal: true

require "test_helper"
require "action_controller"

class TestQueryFromParams < Minitest::Test
  def setup
    setup_query_database
    seed_query_users
  end

  def test_extracts_from_nested_param_key
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    params = ActionController::Parameters.new(user_search: { role: "admin" })
    result = query_class.from_params(params).resolve
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_strips_blanks_for_optional_props
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    params = ActionController::Parameters.new(user_search: { role: "" })
    query = query_class.from_params(params)
    assert_nil query.role
  end

  def test_compacts_array_blanks
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :role, _Array(String)
      filter :role, :in
    end

    params = ActionController::Parameters.new(user_search: { role: ["admin", ""] })
    query = query_class.from_params(params)
    assert_equal ["admin"], query.role
  end

  def test_coerces_optional_integer_array_elements
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :ages, _Array(Integer)
      filter(:ages) { |scope, value| scope.where(age: value) }
    end

    params = ActionController::Parameters.new(user_search: { ages: ["25", "30", ""] })
    query = query_class.from_params(params)
    assert_equal [25, 30], query.ages
  end

  def test_coerces_integer
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :age, Integer
      filter :age, :gte
    end

    params = ActionController::Parameters.new(user_search: { age: "25" })
    result = query_class.from_params(params).resolve
    assert_equal 3, result.count
  end

  def test_coerces_date
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :since, Date
      filter(:since) { |scope, value| scope.where("created_at >= ?", value) }
    end

    params = ActionController::Parameters.new(user_search: { since: "2020-01-01" })
    query = query_class.from_params(params)
    assert_kind_of Date, query.since
  end

  def test_drops_uncoercible_to_nil
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :age, Integer
      filter :age
    end

    params = ActionController::Parameters.new(user_search: { age: "not_a_number" })
    query = query_class.from_params(params)
    assert_nil query.age
  end

  def test_keyword_overrides
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    params = ActionController::Parameters.new(user_search: { role: "user" })
    result = query_class.from_params(params, role: "admin").resolve
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_sort_override_wins_over_params
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      sort :name, :age
    end

    params = ActionController::Parameters.new(user_search: { sort: "age" })
    result = query_class.from_params(params, sort: "-name").resolve
    assert_equal %w[Charlie Bob Alice], result.map(&:name)
  end

  def test_scope_passed_through
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    injected = QueryUser.where(status: "active")
    params = ActionController::Parameters.new(user_search: { role: "user" })
    result = query_class.from_params(params, scope: injected).resolve
    assert_equal 1, result.count
    assert_equal "Bob", result.first.name
  end

  def test_sort_extracted_from_params
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      sort :name, :age
    end

    params = ActionController::Parameters.new(user_search: { sort: "-name" })
    result = query_class.from_params(params).resolve
    assert_equal %w[Charlie Bob Alice], result.map(&:name)
  end

  def test_invalid_sort_falls_back_to_default
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      sort :name, default: "name"
    end

    params = ActionController::Parameters.new(user_search: { sort: "bogus" })
    result = query_class.from_params(params).resolve
    assert_equal %w[Alice Bob Charlie], result.map(&:name)
  end

  def test_dash_prefix_on_custom_sort_falls_back_to_default
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      sort :name, default: "name"
      sort(:newest) { |scope| scope.order(created_at: :desc) }
    end

    params = ActionController::Parameters.new(user_search: { sort: "-newest" })
    result = query_class.from_params(params).resolve
    assert_equal %w[Alice Bob Charlie], result.map(&:name)
  end

  def test_coerces_integer_with_leading_zero
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :age, Integer
      filter :age, :gte
    end

    params = ActionController::Parameters.new(user_search: { age: "08" })
    query = query_class.from_params(params)
    assert_equal 8, query.age
  end

  def test_plain_hash_params
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    params = { "user_search" => { "role" => "admin" } }
    result = query_class.from_params(params).resolve
    assert_equal 1, result.count
  end

  def test_custom_param_key_in_from_params
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      param_key :q
      prop? :role, String
      filter :role
    end

    params = ActionController::Parameters.new(q: { role: "admin" })
    result = query_class.from_params(params).resolve
    assert_equal 1, result.count
  end

  def test_scalar_nested_param_treated_as_empty
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    params = ActionController::Parameters.new(user_search: "foo")
    result = query_class.from_params(params).resolve
    assert_equal 3, result.count
  end

  def test_ref_props_excluded_from_params
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :project, _Ref(QueryUser)
    end

    params = ActionController::Parameters.new(user_search: { project: "1" })
    query = query_class.from_params(params)
    assert_nil query.project
  end

  def test_blank_input_overrides_prop_default_to_nil
    query_class = define_query(:UserSearch, scope_model: QueryUser) do
      prop? :role, String, default: "user"
      filter :role
    end

    params = ActionController::Parameters.new(user_search: { role: "" })
    query = query_class.from_params(params)
    assert_nil query.role

    result = query.resolve
    assert_equal 3, result.count
  end
end
