# frozen_string_literal: true

require "test_helper"

class TestFormAttributes < Minitest::Test
  def test_string_attribute
    form_class = build_form do
      attribute :name, :string
    end

    form = form_class.new(name: "Alice")
    assert_equal "Alice", form.name
  end

  def test_integer_attribute
    form_class = build_form do
      attribute :age, :integer
    end

    form = form_class.new(age: "30")
    assert_equal 30, form.age
  end

  def test_boolean_attribute
    form_class = build_form do
      attribute :active, :boolean
    end

    form = form_class.new(active: "1")
    assert_equal true, form.active
  end

  def test_date_attribute
    form_class = build_form do
      attribute :born_on, :date
    end

    form = form_class.new(born_on: "2000-01-15")
    assert_equal Date.new(2000, 1, 15), form.born_on
  end

  def test_default_value
    form_class = build_form do
      attribute :role, :string, default: "member"
    end

    form = form_class.new
    assert_equal "member", form.role
  end

  def test_nil_attribute
    form_class = build_form do
      attribute :name, :string
    end

    form = form_class.new
    assert_nil form.name
  end

  def test_multiple_attributes
    form_class = build_form do
      attribute :name, :string
      attribute :age, :integer
      attribute :email, :string
    end

    form = form_class.new(name: "Alice", age: 30, email: "alice@example.com")
    assert_equal "Alice", form.name
    assert_equal 30, form.age
    assert_equal "alice@example.com", form.email
  end

  def test_assign_attributes
    form_class = build_form do
      attribute :name, :string
      attribute :email, :string
    end

    form = form_class.new(name: "Alice")
    form.assign_attributes(email: "alice@example.com")
    assert_equal "Alice", form.name
    assert_equal "alice@example.com", form.email
  end

  def test_attribute_names
    form_class = build_form do
      attribute :name, :string
      attribute :email, :string
    end

    assert_includes form_class.attribute_names, "name"
    assert_includes form_class.attribute_names, "email"
  end

  def test_string_keys
    form_class = build_form do
      attribute :name, :string
    end

    form = form_class.new("name" => "Alice")
    assert_equal "Alice", form.name
  end

  def test_unknown_keys_are_silently_ignored
    form_class = build_form do
      attribute :name, :string
    end

    form = form_class.new(name: "Alice", unknown: "value", another: 123)
    assert_equal "Alice", form.name
    assert_equal({ name: "Alice" }, form.to_h)
  end
end
