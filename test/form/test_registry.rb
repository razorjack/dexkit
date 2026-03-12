# frozen_string_literal: true

require "test_helper"

class TestFormRegistry < Minitest::Test
  def teardown
    Dex::Form.clear!
    super
  end

  def test_subclass_registered
    form_class = define_form(:RegisteredForm) do
      field :name, :string
    end

    assert_includes Dex::Form.registry, form_class
  end

  def test_anonymous_not_in_registry
    build_form do
      field :name, :string
    end

    # Anonymous classes are filtered out by Registry
    Dex::Form.registry.each do |klass|
      assert klass.name, "anonymous class should not be in registry"
    end
  end

  def test_description
    form_class = define_form(:DescribedForm) do
      description "Accepts order input"
      field :name, :string
    end

    assert_equal "Accepts order input", form_class.description
  end

  def test_description_nil_by_default
    form_class = define_form(:NoDescForm) do
      field :name, :string
    end

    assert_nil form_class.description
  end

  def test_description_inherited
    parent = define_form(:ParentDescForm) do
      description "Parent description"
    end

    child = define_form(:ChildDescForm, parent: parent) {}

    assert_equal "Parent description", child.description
  end

  def test_description_overridden
    parent = define_form(:ParentOverrideForm) do
      description "Parent"
    end

    child = define_form(:ChildOverrideForm, parent: parent) do
      description "Child"
    end

    assert_equal "Child", child.description
    assert_equal "Parent", parent.description
  end

  def test_description_validates_type
    err = assert_raises(ArgumentError) do
      build_form { description 123 }
    end
    assert_match(/must be a String/, err.message)
  end

  def test_registry_returns_frozen_set
    define_form(:FrozenSetForm) do
      field :name, :string
    end

    assert Dex::Form.registry.frozen?
  end

  def test_deregister
    form_class = define_form(:DeregForm) do
      field :name, :string
    end

    Dex::Form.deregister(form_class)
    refute_includes Dex::Form.registry, form_class
  end

  def test_nested_forms_excluded_from_registry
    define_form(:RegistryParentForm) do
      field :name, :string

      nested_one :address do
        field :street, :string
      end

      nested_many :documents do
        field :doc_type, :string
      end
    end

    names = Dex::Form.registry.map(&:name)
    assert_includes names, "RegistryParentForm"
    refute names.any? { |n| n.include?("::Address") }
    refute names.any? { |n| n.include?("::Document") }
  end
end
