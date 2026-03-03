# frozen_string_literal: true

require "test_helper"

class TestFormSerialization < Minitest::Test
  def test_to_h_returns_attributes
    form_class = build_form do
      attribute :name, :string
      attribute :age, :integer
    end

    form = form_class.new(name: "Alice", age: 30)
    assert_equal({ name: "Alice", age: 30 }, form.to_h)
  end

  def test_to_hash_alias
    form_class = build_form do
      attribute :name, :string
    end

    form = form_class.new(name: "Alice")
    assert_equal form.to_h, form.to_hash
  end

  def test_to_h_with_nil_values
    form_class = build_form do
      attribute :name, :string
      attribute :email, :string
    end

    form = form_class.new(name: "Alice")
    h = form.to_h
    assert_equal "Alice", h[:name]
    assert_nil h[:email]
  end

  def test_to_h_with_nested_one
    form_class = build_form do
      attribute :name, :string
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new(name: "Alice", address: { street: "123 Main" })
    expected = { name: "Alice", address: { street: "123 Main" } }
    assert_equal expected, form.to_h
  end

  def test_to_h_with_nil_nested_one
    form_class = build_form do
      attribute :name, :string
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new(name: "Alice")
    form.address = nil
    assert_nil form.to_h[:address]
  end

  def test_to_h_with_nested_many
    form_class = build_form do
      nested_many :items do
        attribute :label, :string
      end
    end

    form = form_class.new(items: [{ label: "A" }, { label: "B" }])
    assert_equal [{ label: "A" }, { label: "B" }], form.to_h[:items]
  end

  def test_to_h_with_empty_nested_many
    form_class = build_form do
      nested_many :items do
        attribute :label, :string
      end
    end

    form = form_class.new
    assert_equal [], form.to_h[:items]
  end
end
