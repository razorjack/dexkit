# frozen_string_literal: true

require "test_helper"

class TestQueryRegistry < Minitest::Test
  def setup
    setup_query_database
  end

  def teardown
    Dex::Query.clear!
    super
  end

  def test_registry_returns_frozen_set
    result = Dex::Query.registry
    assert_instance_of Set, result
    assert result.frozen?
  end

  def test_named_subclass_registered
    define_query(:RegisteredQuery, scope_model: QueryUser)
    assert_includes Dex::Query.registry, RegisteredQuery
  end

  def test_anonymous_subclass_excluded
    build_query(scope_model: QueryUser)
    Dex::Query.registry.each do |klass|
      assert klass.name, "anonymous class should not be in registry"
    end
  end

  def test_deregister
    query_class = define_query(:DeregQuery, scope_model: QueryUser)
    assert_includes Dex::Query.registry, query_class
    Dex::Query.deregister(query_class)
    refute_includes Dex::Query.registry, query_class
  end

  # --- description ---

  def test_description
    query_class = build_query(scope_model: QueryUser) do
      description "Find active employees"
    end
    assert_equal "Find active employees", query_class.description
  end

  def test_description_nil_by_default
    query_class = build_query(scope_model: QueryUser)
    assert_nil query_class.description
  end

  def test_description_inherited
    parent = build_query(scope_model: QueryUser) do
      description "Parent description"
    end
    child = build_query(parent: parent)
    assert_equal "Parent description", child.description
  end

  def test_description_overridden
    parent = build_query(scope_model: QueryUser) do
      description "Parent"
    end
    child = build_query(parent: parent) do
      description "Child"
    end
    assert_equal "Child", child.description
    assert_equal "Parent", parent.description
  end

  def test_description_validates_type
    err = assert_raises(ArgumentError) do
      build_query(scope_model: QueryUser) { description 123 }
    end
    assert_match(/must be a String/, err.message)
  end
end
