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

  def test_to_h_includes_name
    define_query(:ExportHashQuery, scope_model: QueryUser)
    h = ExportHashQuery.to_h
    assert_equal "ExportHashQuery", h[:name]
  end

  def test_to_h_includes_description
    query_class = build_query(scope_model: QueryUser) do
      description "Find users"
    end
    h = query_class.to_h
    assert_equal "Find users", h[:description]
  end

  def test_to_h_omits_description_when_nil
    query_class = build_query(scope_model: QueryUser)
    h = query_class.to_h
    refute h.key?(:description)
  end

  def test_to_h_serializes_props
    query_class = build_query(scope_model: QueryUser) do
      prop? :name, String, desc: "Filter by name"
      prop? :age, Integer
    end
    h = query_class.to_h
    assert_equal "Nilable(String)", h[:props][:name][:type]
    refute h[:props][:name][:required]
    assert_equal "Filter by name", h[:props][:name][:desc]
    assert_equal "Nilable(Integer)", h[:props][:age][:type]
    refute h[:props][:age].key?(:desc)
  end

  def test_to_h_includes_context
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      context role: :current_role
    end
    h = query_class.to_h
    assert_equal({ role: :current_role }, h[:context])
  end

  def test_to_h_context_omitted_when_none
    query_class = build_query(scope_model: QueryUser)
    h = query_class.to_h
    refute h.key?(:context)
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

  def test_to_json_schema_basic
    query_class = define_query(:SchemaQuery, scope_model: QueryUser) do
      description "Schema test"
      prop :order_id, Integer
      prop? :note, String
    end
    schema = query_class.to_json_schema
    assert_equal "https://json-schema.org/draft/2020-12/schema", schema[:$schema]
    assert_equal "SchemaQuery", schema[:title]
    assert_equal "Schema test", schema[:description]
    assert_equal "object", schema[:type]
    assert_equal({ type: "integer" }, schema[:properties]["order_id"])
    assert_includes schema[:required], "order_id"
    refute_includes(schema[:required] || [], "note")
    assert_equal false, schema[:additionalProperties]
  end

  def test_to_json_schema_with_prop_desc
    query_class = build_query(scope_model: QueryUser) do
      prop? :name, String, desc: "Filter by name"
    end
    schema = query_class.to_json_schema
    props = schema[:properties]["name"]
    assert_equal "Filter by name", props[:description]
  end

  def test_to_json_schema_optional_prop_not_required
    query_class = build_query(scope_model: QueryUser) do
      prop? :name, String
    end
    schema = query_class.to_json_schema
    refute schema.key?(:required)
  end

  # --- Global export ---

  def test_export_hash
    define_query(:ExportAQuery, scope_model: QueryUser)
    define_query(:ExportBQuery, scope_model: QueryUser)

    result = Dex::Query.export(format: :hash)
    names = result.map { |h| h[:name] }
    assert_includes names, "ExportAQuery"
    assert_includes names, "ExportBQuery"
  end

  def test_export_sorted_by_name
    define_query(:ExportZQuery, scope_model: QueryUser)
    define_query(:ExportAQuery, scope_model: QueryUser)

    result = Dex::Query.export
    names = result.map { |h| h[:name] }
    idx_a = names.index("ExportAQuery")
    idx_z = names.index("ExportZQuery")
    assert idx_a < idx_z
  end

  def test_export_json_schema
    define_query(:SchemaExportQuery, scope_model: QueryUser) do
      prop? :name, String
    end

    result = Dex::Query.export(format: :json_schema)
    assert result.all? { |s| s[:type] == "object" }
  end

  def test_export_invalid_format
    err = assert_raises(ArgumentError) do
      Dex::Query.export(format: :xml)
    end
    assert_match(/unknown format/, err.message)
  end
end
