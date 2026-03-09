# frozen_string_literal: true

require "test_helper"
require "mongoid"

class TestQueryMongoidScopeNormalization < Minitest::Test
  PARENT_CONST = :MongoidScopeParent
  CHILD_CONST = :MongoidScopeChild

  def setup
    _configure_mongoid!

    Object.send(:remove_const, PARENT_CONST) if Object.const_defined?(PARENT_CONST)
    Object.send(:remove_const, CHILD_CONST) if Object.const_defined?(CHILD_CONST)

    parent_class = Class.new do
      include Mongoid::Document

      field :name, type: String
      has_many :children, class_name: CHILD_CONST.to_s, inverse_of: :parent
    end

    child_class = Class.new do
      include Mongoid::Document

      field :name, type: String
      field :active, type: Mongoid::Boolean
      belongs_to :parent, class_name: PARENT_CONST.to_s, inverse_of: :children, optional: true
    end

    Object.const_set(PARENT_CONST, parent_class)
    Object.const_set(CHILD_CONST, child_class)
  end

  def teardown
    Object.send(:remove_const, PARENT_CONST) if Object.const_defined?(PARENT_CONST)
    Object.send(:remove_const, CHILD_CONST) if Object.const_defined?(CHILD_CONST)
    super
  end

  def test_backend_detects_mongoid_association_scope
    parent = Object.const_get(PARENT_CONST).new
    adapter = Dex::Query::Backend.adapter_for(parent.children)

    assert_equal Dex::Query::Backend::MongoidAdapter, adapter
  end

  def test_filters_normalize_association_scope_to_criteria
    parent_class = Object.const_get(PARENT_CONST)

    query_class = build_query do
      scope { parent_class.new.children }
      prop? :name, String
      filter :name, :contains
    end

    result = query_class.call(name: "al")

    assert_kind_of Mongoid::Criteria, result
  end

  def test_injected_scope_merges_after_normalizing_association_scope
    parent_class = Object.const_get(PARENT_CONST)
    child_class = Object.const_get(CHILD_CONST)

    query_class = build_query do
      scope { parent_class.new.children }
      prop? :name, String
      filter :name, :contains
    end

    result = query_class.call(scope: child_class.where(active: true), name: "al")

    assert_kind_of Mongoid::Criteria, result
  end
end
