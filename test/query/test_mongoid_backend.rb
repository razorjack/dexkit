# frozen_string_literal: true

require "test_helper"
require "action_controller"

class TestQueryMongoidBackend < Minitest::Test
  def setup
    setup_mongoid_query_database
    seed_query_users
  end

  def test_call_returns_mongoid_criteria
    query_class = build_query do
      scope { MongoQueryUser.all }
    end

    result = query_class.call
    assert_kind_of Mongoid::Criteria, result
    assert_equal 3, result.count
  end

  def test_backend_auto_detects_mongoid_adapter
    adapter = Dex::Query::Backend.adapter_for(MongoQueryUser.all)
    assert_equal Dex::Query::Backend::MongoidAdapter, adapter
  end

  def test_eq_and_not_eq_strategies
    query_class = build_query do
      scope { MongoQueryUser.all }
      prop? :role, String
      filter :role
    end

    admin_result = query_class.call(role: "admin")
    assert_equal ["Alice"], admin_result.map(&:name)

    query_class_not_eq = build_query do
      scope { MongoQueryUser.all }
      prop? :role, String
      filter :role, :not_eq
    end

    not_admin = query_class_not_eq.call(role: "admin")
    assert_equal %w[Bob Charlie], not_admin.map(&:name).sort
  end

  def test_string_strategies_are_case_insensitive
    contains_query = build_query do
      scope { MongoQueryUser.all }
      prop? :name, String
      filter :name, :contains
    end

    contains_result = contains_query.call(name: "AL")
    assert_equal ["Alice"], contains_result.map(&:name)

    starts_with_query = build_query do
      scope { MongoQueryUser.all }
      prop? :name, String
      filter :name, :starts_with
    end

    starts_with_result = starts_with_query.call(name: "ch")
    assert_equal ["Charlie"], starts_with_result.map(&:name)

    ends_with_query = build_query do
      scope { MongoQueryUser.all }
      prop? :name, String
      filter :name, :ends_with
    end

    ends_with_result = ends_with_query.call(name: "OB")
    assert_equal ["Bob"], ends_with_result.map(&:name)
  end

  def test_comparison_strategies
    gt_query = build_query do
      scope { MongoQueryUser.all }
      prop? :age, Integer
      filter :age, :gt
    end
    assert_equal %w[Alice Charlie], gt_query.call(age: 29).map(&:name).sort

    gte_query = build_query do
      scope { MongoQueryUser.all }
      prop? :age, Integer
      filter :age, :gte
    end
    assert_equal %w[Alice Charlie], gte_query.call(age: 30).map(&:name).sort

    lt_query = build_query do
      scope { MongoQueryUser.all }
      prop? :age, Integer
      filter :age, :lt
    end
    assert_equal ["Bob"], lt_query.call(age: 30).map(&:name)

    lte_query = build_query do
      scope { MongoQueryUser.all }
      prop? :age, Integer
      filter :age, :lte
    end
    assert_equal %w[Alice Bob], lte_query.call(age: 30).map(&:name).sort
  end

  def test_in_and_not_in_strategies
    in_query = build_query do
      scope { MongoQueryUser.all }
      prop? :role, _Array(String)
      filter :role, :in
    end
    assert_equal 3, in_query.call(role: %w[admin user]).count

    not_in_query = build_query do
      scope { MongoQueryUser.all }
      prop? :role, _Array(String)
      filter :role, :not_in
    end
    assert_equal %w[Bob Charlie], not_in_query.call(role: ["admin"]).map(&:name).sort
  end

  def test_contains_escapes_regex_metacharacters
    MongoQueryUser.create!(name: "Test%User", email: "test@example.com", role: "user", age: 20, status: "active")

    query_class = build_query do
      scope { MongoQueryUser.all }
      prop? :name, String
      filter :name, :contains
    end

    result = query_class.call(name: "%")
    assert_equal ["Test%User"], result.map(&:name)
  end

  def test_sorting_and_default_sort
    query_class = build_query do
      scope { MongoQueryUser.all }
      sort :name, :age, default: "-name"
    end

    ascending = query_class.call(sort: "age")
    assert_equal %w[Bob Alice Charlie], ascending.map(&:name)

    descending = query_class.call(sort: "-name")
    assert_equal %w[Charlie Bob Alice], descending.map(&:name)

    default_sorted = query_class.call
    assert_equal %w[Charlie Bob Alice], default_sorted.map(&:name)
  end

  def test_custom_sort_block
    query_class = build_query do
      scope { MongoQueryUser.all }
      sort(:newest) { |scope| scope.order_by(created_at: :desc) }
    end

    result = query_class.call(sort: "newest")
    assert_equal "Bob", result.first.name
  end

  def test_scope_injection_merges_mongoid_criteria
    query_class = build_query do
      scope { MongoQueryUser.all }
      prop? :role, String
      filter :role
    end

    injected = MongoQueryUser.where(status: "active")
    result = query_class.call(scope: injected, role: "user")

    assert_equal ["Bob"], result.map(&:name)
  end

  def test_scope_injection_validates_queryable_scope
    query_class = build_query do
      scope { MongoQueryUser.all }
    end

    error = assert_raises(ArgumentError) do
      query_class.call(scope: "not a criteria")
    end

    assert_match(/Injected scope must be a queryable scope/, error.message)
  end

  def test_from_params_coercion_and_sorting
    query_class = define_query(:MongoUserSearch) do
      scope { MongoQueryUser.all }
      prop? :age, Integer
      prop? :role, String
      filter :age, :gte
      filter :role
      sort :name
    end

    params = ActionController::Parameters.new(mongo_user_search: { age: "30", role: "user", sort: "-name" })
    result = query_class.from_params(params).resolve

    assert_equal ["Charlie"], result.map(&:name)
  end

  private

  def seed_query_users
    MongoQueryUser.create!(name: "Charlie", email: "charlie@example.com", role: "user", age: 35, status: "inactive")
    MongoQueryUser.create!(name: "Alice", email: "alice@example.com", role: "admin", age: 30, status: "active")
    MongoQueryUser.create!(name: "Bob", email: "bob@example.com", role: "user", age: 25, status: "active")
  end
end
