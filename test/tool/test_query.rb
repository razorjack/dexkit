# frozen_string_literal: true

require "test_helper"

# Stub ruby-llm for testing
unless defined?(RubyLLM::Tool)
  module RubyLLM
    class Tool; end
  end
end

silence_redefinition_of_method = $VERBOSE
$VERBOSE = nil
Dex::Tool.define_singleton_method(:_require_ruby_llm!) {}
$VERBOSE = silence_redefinition_of_method

class TestToolQuery < Minitest::Test
  def setup
    setup_query_database
    seed_query_users
  end

  # --- from dispatch ---

  def test_from_dispatches_to_query_tool
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })
    assert_kind_of RubyLLM::Tool, tool
    assert_match(/dex_query_/, tool.name)
  end

  def test_from_raises_for_unknown_class
    err = assert_raises(ArgumentError) { Dex::Tool.from(String) }
    assert_match(/expected a Dex::Operation or Dex::Query subclass/, err.message)
  end

  # --- Tool name ---

  def test_tool_name_format
    query_class = define_query(:ToolNameQuery, scope_model: QueryUser) do
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })
    assert_equal "dex_query_toolnamequery", tool.name
  end

  # --- Validation: required options ---

  def test_missing_scope_raises
    query_class = build_query(scope_model: QueryUser)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, serialize: ->(r) { r })
    end
    assert_match(/Query tools require scope: and serialize:/, err.message)
  end

  def test_missing_serialize_raises
    query_class = build_query(scope_model: QueryUser)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: -> { QueryUser.all })
    end
    assert_match(/Query tools require serialize:/, err.message)
  end

  def test_no_scope_block_raises
    query_class = Class.new(Dex::Query)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all },
        serialize: ->(r) { r })
    end
    assert_match(/has no scope block/, err.message)
  end

  def test_scope_not_callable_raises
    query_class = build_query(scope_model: QueryUser)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: "not_callable", serialize: ->(r) { r })
    end
    assert_match(/scope: must respond to call/, err.message)
  end

  def test_serialize_not_callable_raises
    query_class = build_query(scope_model: QueryUser)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: -> { QueryUser.all }, serialize: "not_callable")
    end
    assert_match(/serialize: must respond to call/, err.message)
  end

  # --- Validation: limit ---

  def test_limit_zero_raises
    query_class = build_query(scope_model: QueryUser)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: -> { QueryUser.all }, serialize: ->(r) { r }, limit: 0)
    end
    assert_match(/limit: must be a positive integer/, err.message)
  end

  def test_limit_negative_raises
    query_class = build_query(scope_model: QueryUser)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: -> { QueryUser.all }, serialize: ->(r) { r }, limit: -1)
    end
    assert_match(/limit: must be a positive integer/, err.message)
  end

  def test_limit_non_integer_raises
    query_class = build_query(scope_model: QueryUser)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: -> { QueryUser.all }, serialize: ->(r) { r }, limit: "10")
    end
    assert_match(/limit: must be a positive integer/, err.message)
  end

  # --- Validation: filter restrictions ---

  def test_only_filters_and_except_filters_raises
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        only_filters: [:role], except_filters: [:role])
    end
    assert_match(/mutually exclusive/, err.message)
  end

  def test_only_filters_unknown_raises
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        only_filters: [:bogus])
    end
    assert_match(/unknown filter :bogus/, err.message)
    assert_match(/Declared:/, err.message)
  end

  def test_except_filters_unknown_raises
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        except_filters: [:bogus])
    end
    assert_match(/unknown filter :bogus in except_filters/, err.message)
  end

  # --- Validation: sort restrictions ---

  def test_only_sorts_unknown_raises
    query_class = build_query(scope_model: QueryUser) do
      sort :name
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        only_sorts: [:bogus])
    end
    assert_match(/unknown sort :bogus/, err.message)
  end

  def test_default_sort_outside_only_sorts_raises
    query_class = build_query(scope_model: QueryUser) do
      sort :name, :age, default: "name"
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        only_sorts: [:age])
    end
    assert_match(/query default sort name is not in only_sorts/, err.message)
  end

  # --- Validation: prop conflicts ---

  def test_prop_named_limit_raises
    query_class = build_query(scope_model: QueryUser) do
      prop? :limit, Integer
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: -> { QueryUser.all }, serialize: ->(r) { r })
    end
    assert_match(/prop :limit which conflicts/, err.message)
  end

  def test_prop_named_offset_raises
    query_class = build_query(scope_model: QueryUser) do
      prop? :offset, Integer
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: -> { QueryUser.all }, serialize: ->(r) { r })
    end
    assert_match(/prop :offset which conflicts/, err.message)
  end

  # --- Validation: unsatisfiable props ---

  def test_required_ref_prop_unsatisfiable_raises
    query_class = build_query(scope_model: QueryUser) do
      prop :user, _Ref(QueryUser)
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class, scope: -> { QueryUser.all }, serialize: ->(r) { r })
    end
    assert_match(/prop :user \(_Ref\) is auto-excluded/, err.message)
  end

  def test_required_ref_prop_with_context_is_satisfiable
    query_class = build_query(scope_model: QueryUser) do
      prop :user, _Ref(QueryUser)
      context user: :current_user
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })
    assert_kind_of RubyLLM::Tool, tool
  end

  def test_excluded_filter_hides_unsatisfiable_prop_raises
    query_class = build_query(scope_model: QueryUser) do
      prop :role, String
      filter :role
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        except_filters: [:role])
    end
    assert_match(/excluding filter :role hides required prop :role/, err.message)
  end

  # --- Validation: operation with query kwargs ---

  def test_operation_with_scope_kwarg_raises
    op = Class.new(Dex::Operation) do
      def perform
      end
    end
    op.define_singleton_method(:name) { "TestOp" }

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(op, scope: -> { "test" })
    end
    assert_match(/scope: is not a valid option for Operation tools/, err.message)
  end

  def test_unknown_option_raises
    query_class = build_query(scope_model: QueryUser)
    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        bogus: true)
    end
    assert_match(/unknown option/, err.message)
  end

  # --- Schema: params ---

  def test_schema_includes_regular_props
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String, desc: "Filter by role"
      prop? :age, Integer
      filter :role
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    props = tool.params_schema[:properties]
    assert props.key?("role")
    assert props.key?("age")
    assert_equal "Filter by role", props["role"][:description]
  end

  def test_schema_excludes_context_mapped_props
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
      context :role
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    props = tool.params_schema[:properties]
    refute props.key?("role")
    assert props.key?("status")
  end

  def test_schema_excludes_ref_props
    query_class = build_query(scope_model: QueryUser) do
      prop? :user, _Ref(QueryUser)
      prop? :status, String
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    props = tool.params_schema[:properties]
    refute props.key?("user")
    assert props.key?("status")
  end

  def test_schema_excludes_props_backing_excluded_filters
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json },
      except_filters: [:status])

    props = tool.params_schema[:properties]
    assert props.key?("role")
    refute props.key?("status")
  end

  def test_schema_sort_enum
    query_class = build_query(scope_model: QueryUser) do
      sort :name, :age, default: "-name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    sort_prop = tool.params_schema[:properties]["sort"]
    assert_equal %w[name -name age -age], sort_prop[:enum]
    assert_match(/Default: -name/, sort_prop[:description])
  end

  def test_schema_sort_custom_no_dash_prefix
    query_class = build_query(scope_model: QueryUser) do
      sort(:relevance) { |scope| scope.order(Arel.sql("1")) }
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    sort_prop = tool.params_schema[:properties]["sort"]
    assert_includes sort_prop[:enum], "relevance"
    refute_includes sort_prop[:enum], "-relevance"
  end

  def test_schema_sort_respects_only_sorts
    query_class = build_query(scope_model: QueryUser) do
      sort :name, :age, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json },
      only_sorts: [:name])

    sort_prop = tool.params_schema[:properties]["sort"]
    assert_equal %w[name -name], sort_prop[:enum]
  end

  def test_schema_has_limit_and_offset
    query_class = build_query(scope_model: QueryUser)

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json },
      limit: 25)

    props = tool.params_schema[:properties]
    assert_equal "integer", props["limit"][:type]
    assert_match(/max: 25/, props["limit"][:description])
    assert_equal "integer", props["offset"][:type]
  end

  def test_schema_required_props
    query_class = build_query(scope_model: QueryUser) do
      prop :name, String
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    assert_includes tool.params_schema[:required], "name"
  end

  # --- Description ---

  def test_description_uses_query_description
    query_class = build_query(scope_model: QueryUser) do
      description "Search users"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    assert tool.description.start_with?("Search users.")
  end

  def test_description_filters_with_union_values
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, _Union("admin", "user")
      filter :role
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    assert_match(/role \(admin or user\)/, tool.description)
  end

  def test_description_filters_with_desc
    query_class = build_query(scope_model: QueryUser) do
      prop? :age, Integer, desc: "Minimum age"
      filter :age, :gte
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    assert_match(/age \(Minimum age\)/, tool.description)
  end

  def test_description_sorts_with_default
    query_class = build_query(scope_model: QueryUser) do
      sort :name, :age, default: "-name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    assert_match(/Sorts: name \(default: -name\), age/, tool.description)
  end

  def test_description_limit_info
    query_class = build_query(scope_model: QueryUser)

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json },
      limit: 25)

    assert_match(/Returns up to 25 results/, tool.description)
  end

  # --- Execution ---

  def test_execute_returns_records
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })

    result = tool.execute(role: "admin")
    assert_equal 1, result[:records].size
    assert_equal "Alice", result[:records].first[:name]
    assert_equal 1, result[:total]
  end

  def test_execute_returns_all_without_filter
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })

    result = tool.execute
    assert_equal 3, result[:records].size
    assert_equal 3, result[:total]
  end

  def test_execute_sorting
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })

    result = tool.execute(sort: "-name")
    names = result[:records].map { |r| r[:name] }
    assert_equal %w[Charlie Bob Alice], names
  end

  def test_execute_invalid_sort_falls_back_to_default
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })

    result = tool.execute(sort: "bogus")
    names = result[:records].map { |r| r[:name] }
    assert_equal %w[Alice Bob Charlie], names
  end

  def test_execute_pagination
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } },
      limit: 2)

    result = tool.execute(limit: 2, offset: 1)
    assert_equal 2, result[:records].size
    assert_equal 3, result[:total]
    assert_equal 2, result[:limit]
    assert_equal 1, result[:offset]
    assert_equal "Bob", result[:records].first[:name]
  end

  def test_execute_clamps_limit_to_max
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } },
      limit: 2)

    result = tool.execute(limit: 100)
    assert_equal 2, result[:limit]
  end

  def test_execute_scope_injection
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.where(status: "active") },
      serialize: ->(r) { { name: r.name } })

    result = tool.execute
    names = result[:records].map { |r| r[:name] }
    assert_equal %w[Alice Bob], names
    assert_equal 2, result[:total]
  end

  def test_execute_strips_context_keys
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
      context :status
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })

    # Agent sends status, but it should be stripped (context-mapped)
    result = tool.execute(status: "inactive", role: "user")
    assert_equal 2, result[:records].size
  end

  def test_execute_error_returns_structured_error
    query_class = build_query(scope_model: QueryUser) do
      prop :required_field, String
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { r.as_json })

    result = tool.execute
    assert_equal "invalid_params", result[:error]
    assert result[:message].is_a?(String)
  end

  def test_execute_serializer_applied
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { id: r.id, upcase_name: r.name.upcase } })

    result = tool.execute
    assert result[:records].first.key?(:upcase_name)
    assert_equal "ALICE", result[:records].first[:upcase_name]
  end

  def test_execute_default_limit_is_50
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })

    result = tool.execute
    assert_equal 50, result[:limit]
  end

  def test_execute_strips_excluded_filter_keys
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } },
      except_filters: [:status])

    # Agent sends excluded filter — must be stripped at runtime
    result = tool.execute(status: "inactive")
    assert_equal 3, result[:records].size
  end

  def test_execute_strips_only_filters_excluded_keys
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      prop? :status, String
      filter :role
      filter :status
      sort :name, default: "name"
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } },
      only_filters: [:role])

    # Agent sends non-allowed filter — must be stripped
    result = tool.execute(status: "inactive")
    assert_equal 3, result[:records].size
  end

  def test_only_filters_context_mapped_raises
    query_class = build_query(scope_model: QueryUser) do
      prop? :role, String
      filter :role
      context :role
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        only_filters: [:role])
    end
    assert_match(/context-mapped/, err.message)
    assert_match(/Remove it from only_filters/, err.message)
  end

  def test_only_filters_ref_backed_raises
    query_class = build_query(scope_model: QueryUser) do
      prop? :user, _Ref(QueryUser)
      filter(:user) { |scope, _v| scope }
    end

    err = assert_raises(ArgumentError) do
      Dex::Tool.from(query_class,
        scope: -> { QueryUser.all }, serialize: ->(r) { r },
        only_filters: [:user])
    end
    assert_match(/_Ref prop/, err.message)
    assert_match(/Remove it from only_filters/, err.message)
  end

  def test_execute_dash_on_custom_sort_falls_back
    query_class = build_query(scope_model: QueryUser) do
      sort :name, default: "name"
      sort(:newest) { |scope| scope.order(created_at: :desc) }
    end

    tool = Dex::Tool.from(query_class,
      scope: -> { QueryUser.all },
      serialize: ->(r) { { name: r.name } })

    result = tool.execute(sort: "-newest")
    # Falls back to default sort (name asc)
    assert_equal "Alice", result[:records].first[:name]
  end
end
