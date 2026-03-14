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

  def test_registration_and_deregistration
    query_class = define_query(:RegisteredQuery, scope_model: QueryUser)
    assert_includes Dex::Query.registry, query_class

    Dex::Query.deregister(query_class)
    refute_includes Dex::Query.registry, query_class
  end

  def test_description
    query_class = build_query(scope_model: QueryUser) do
      description "Find active employees"
    end
    assert_equal "Find active employees", query_class.description
  end
end
