# frozen_string_literal: true

require "test_helper"

class TestFormRegistry < Minitest::Test
  def teardown
    Dex::Form.clear!
    super
  end

  def test_registration_and_deregistration
    form_class = define_form(:RegisteredForm) do
      field :name, :string
    end

    assert_includes Dex::Form.registry, form_class

    Dex::Form.deregister(form_class)
    refute_includes Dex::Form.registry, form_class
  end

  def test_description
    form_class = define_form(:DescribedForm) do
      description "Accepts order input"
      field :name, :string
    end

    assert_equal "Accepts order input", form_class.description
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
