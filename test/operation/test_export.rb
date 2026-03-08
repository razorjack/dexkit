# frozen_string_literal: true

require "test_helper"

class TestOperationExport < Minitest::Test
  # --- description ---

  def test_description_returns_nil_by_default
    op = build_operation { def perform = "ok" }
    assert_nil op.description
  end

  def test_description_stores_and_returns_text
    op = build_operation do
      description "Creates a new user"
      def perform = "ok"
    end
    assert_equal "Creates a new user", op.description
  end

  def test_description_requires_string
    assert_raises(ArgumentError) do
      build_operation { description 42 }
    end
  end

  def test_description_rejects_false
    assert_raises(ArgumentError) do
      build_operation { description false }
    end
  end

  def test_description_inherited_from_parent
    parent = build_operation do
      description "Parent description"
      def perform = "ok"
    end
    child = build_operation(parent: parent)
    assert_equal "Parent description", child.description
  end

  def test_description_overridden_in_child
    parent = build_operation do
      description "Parent"
      def perform = "ok"
    end
    child = build_operation(parent: parent) do
      description "Child"
    end
    assert_equal "Child", child.description
  end

  def test_description_not_inherited_from_base_operation
    assert_nil Dex::Operation.description
  end

  # --- desc: on props ---

  def test_prop_desc_stored
    op = build_operation do
      prop :name, String, desc: "The user name"
      def perform = "ok"
    end
    assert_equal({ name: "The user name" }, op.prop_descriptions)
  end

  def test_prop_desc_optional
    op = build_operation do
      prop :name, String
      def perform = "ok"
    end
    assert_equal({}, op.prop_descriptions)
  end

  def test_prop_desc_on_optional_prop
    op = build_operation do
      prop? :email, String, desc: "Contact email"
      def perform = "ok"
    end
    assert_equal({ email: "Contact email" }, op.prop_descriptions)
  end

  def test_prop_desc_inherited
    parent = build_operation do
      prop :name, String, desc: "Name"
      def perform = "ok"
    end
    child = build_operation(parent: parent) do
      prop :age, Integer, desc: "Age"
    end
    expected = { name: "Name", age: "Age" }
    assert_equal expected, child.prop_descriptions
  end

  def test_prop_desc_rejects_non_string
    assert_raises(ArgumentError) do
      build_operation { prop :name, String, desc: 42 }
    end
  end

  def test_prop_desc_rejects_false
    assert_raises(ArgumentError) do
      build_operation { prop :name, String, desc: false }
    end
  end

  def test_prop_optional_desc_rejects_non_string
    assert_raises(ArgumentError) do
      build_operation { prop? :name, String, desc: :bad }
    end
  end

  def test_prop_desc_cleared_when_child_redefines_prop
    parent = build_operation do
      prop :name, String, desc: "Parent name"
      def perform = "ok"
    end
    child = build_operation(parent: parent) do
      prop :name, Integer
    end
    assert_equal({}, child.prop_descriptions)
  end

  def test_prop_desc_preserved_when_child_redefines_with_new_desc
    parent = build_operation do
      prop :name, String, desc: "Parent name"
      def perform = "ok"
    end
    child = build_operation(parent: parent) do
      prop :name, Integer, desc: "Child name"
    end
    assert_equal({ name: "Child name" }, child.prop_descriptions)
  end

  # --- contract.to_h ---

  def test_to_h_includes_name
    define_operation(:ExportHashOp) { def perform = "ok" }
    h = ExportHashOp.contract.to_h
    assert_equal "ExportHashOp", h[:name]
  end

  def test_to_h_includes_description
    op = build_operation do
      description "Test operation"
      def perform = "ok"
    end
    h = op.contract.to_h
    assert_equal "Test operation", h[:description]
  end

  def test_to_h_omits_description_when_nil
    op = build_operation { def perform = "ok" }
    h = op.contract.to_h
    refute h.key?(:description)
  end

  def test_to_h_serializes_params
    op = build_operation do
      prop :name, String, desc: "The name"
      prop :count, Integer
      def perform = "ok"
    end
    h = op.contract.to_h
    assert_equal "String", h[:params][:name][:type]
    assert h[:params][:name][:required]
    assert_equal "The name", h[:params][:name][:desc]
    assert_equal "Integer", h[:params][:count][:type]
    refute h[:params][:count].key?(:desc)
  end

  def test_to_h_serializes_success_type
    op = build_operation do
      success String
      def perform = "ok"
    end
    h = op.contract.to_h
    assert_equal "String", h[:success]
  end

  def test_to_h_omits_success_when_nil
    op = build_operation { def perform = "ok" }
    h = op.contract.to_h
    refute h.key?(:success)
  end

  def test_to_h_serializes_errors
    op = build_operation do
      error :not_found, :forbidden
      def perform = "ok"
    end
    h = op.contract.to_h
    assert_equal %i[not_found forbidden], h[:errors]
  end

  def test_to_h_omits_errors_when_empty
    op = build_operation { def perform = "ok" }
    h = op.contract.to_h
    refute h.key?(:errors)
  end

  def test_to_h_includes_guards
    op = build_operation do
      guard(:check, "Must be valid") { true }
      def perform = "ok"
    end
    h = op.contract.to_h
    assert_equal 1, h[:guards].size
    assert_equal :check, h[:guards][0][:name]
  end

  def test_to_h_includes_pipeline
    op = build_operation { def perform = "ok" }
    h = op.contract.to_h
    assert_equal %i[result guard once lock record transaction rescue callback], h[:pipeline]
  end

  def test_to_h_includes_settings
    op = build_operation do
      record false
      transaction false
      def perform = "ok"
    end
    h = op.contract.to_h
    refute h[:settings][:record][:enabled]
    refute h[:settings][:transaction][:enabled]
  end

  def test_to_h_includes_context
    op = build_operation do
      prop :user, String
      context user: :current_user
      def perform = "ok"
    end
    h = op.contract.to_h
    assert_equal({ user: :current_user }, h[:context])
  end

  def test_to_h_context_omitted_when_none
    op = build_operation { def perform = "ok" }
    h = op.contract.to_h
    refute h.key?(:context)
  end

  # --- contract.to_json_schema ---

  def test_json_schema_default_params
    op = build_operation do
      prop :name, String
      prop :count, Integer
      def perform = "ok"
    end
    schema = op.contract.to_json_schema
    assert_equal "https://json-schema.org/draft/2020-12/schema", schema[:$schema]
    assert_equal "object", schema[:type]
    assert_equal({ type: "string" }, schema[:properties]["name"])
    assert_equal({ type: "integer" }, schema[:properties]["count"])
    assert_includes schema[:required], "name"
    assert_includes schema[:required], "count"
    assert_equal false, schema[:additionalProperties]
  end

  def test_json_schema_with_description
    op = build_operation do
      description "My operation"
      prop :name, String, desc: "The name"
      def perform = "ok"
    end
    schema = op.contract.to_json_schema
    assert_equal "My operation", schema[:description]
    assert_equal "The name", schema[:properties]["name"][:description]
  end

  def test_json_schema_optional_prop_not_required
    op = build_operation do
      prop? :email, String
      def perform = "ok"
    end
    schema = op.contract.to_json_schema
    refute schema.key?(:required)
  end

  def test_json_schema_section_success
    op = build_operation do
      success Integer
      def perform = 42
    end
    schema = op.contract.to_json_schema(section: :success)
    assert_equal "integer", schema[:type]
  end

  def test_json_schema_section_errors
    op = build_operation do
      error :not_found
      def perform = "ok"
    end
    schema = op.contract.to_json_schema(section: :errors)
    assert schema[:properties].key?("not_found")
  end

  def test_json_schema_section_full
    op = build_operation do
      prop :name, String
      success String
      error :fail
      def perform = "ok"
    end
    schema = op.contract.to_json_schema(section: :full)
    assert schema[:properties].key?(:params)
    assert schema[:properties].key?(:success)
    assert schema[:properties].key?(:errors)
  end

  def test_json_schema_unknown_section_raises
    op = build_operation { def perform = "ok" }
    assert_raises(ArgumentError) { op.contract.to_json_schema(section: :bad) }
  end
end
