# frozen_string_literal: true

require "test_helper"

class TestQueryExport < Minitest::Test
  def setup
    setup_query_database
  end

  def teardown
    Dex::Query.clear!
    super
  end

  # --- Class-level to_h ---

  def test_to_h_basics
    query_class = define_query(:ExportHashQuery, scope_model: QueryUser) do
      description "Find users"
      prop? :role, String
      context role: :current_role
    end

    h = query_class.to_h
    assert_equal "ExportHashQuery", h[:name]
    assert_equal "Find users", h[:description]
    assert_equal({ role: :current_role }, h[:context])

    # Without description or context
    bare = build_query(scope_model: QueryUser)
    bh = bare.to_h
    refute bh.key?(:description)
    refute bh.key?(:context)
  end

  def test_to_h_includes_filters
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
    end
    h = query_class.to_h
    assert_equal %i[role status], h[:filters]
  end

  def test_to_h_omits_filters_when_empty
    query_class = build_query(scope_model: QueryUser)
    h = query_class.to_h
    refute h.key?(:filters)
  end

  def test_to_h_includes_sorts
    query_class = build_query(scope_model: QueryUser) do
      sort :name, :age
    end
    h = query_class.to_h
    assert_equal %i[name age], h[:sorts]
  end

  def test_to_h_omits_sorts_when_empty
    query_class = build_query(scope_model: QueryUser)
    h = query_class.to_h
    refute h.key?(:sorts)
  end

  # --- Class-level to_json_schema ---

  def test_to_json_schema_with_prop_desc
    query_class = build_query(scope_model: QueryUser) do
      prop? :name, String, desc: "Filter by name"
    end
    schema = query_class.to_json_schema
    props = schema[:properties]["name"]
    assert_equal "Filter by name", props[:description]
  end
end
