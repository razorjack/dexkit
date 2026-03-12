# frozen_string_literal: true

require "test_helper"

class TestFormField < Minitest::Test
  # --- field (required) ---

  def test_field_declares_attribute
    form_class = build_form do
      field :name, :string
    end

    form = form_class.new(name: "Alice")
    assert_equal "Alice", form.name
  end

  def test_field_with_type_coercion
    form_class = build_form do
      field :age, :integer
    end

    form = form_class.new(age: "30")
    assert_equal 30, form.age
  end

  def test_field_with_default
    form_class = build_form do
      field :currency, :string, default: "USD"
    end

    form = form_class.new
    assert_equal "USD", form.currency
  end

  def test_field_with_desc
    form_class = build_form do
      field :email, :string, desc: "Customer email"
    end

    field_def = form_class._field_registry[:email]
    assert_equal "Customer email", field_def.desc
  end

  def test_field_tracks_as_required
    form_class = build_form do
      field :name, :string
    end

    field_def = form_class._field_registry[:name]
    assert field_def.required
  end

  def test_field_auto_presence_validation
    form_class = build_form do
      field :name, :string
    end

    form = form_class.new(name: "")
    assert form.invalid?
    assert_includes form.errors[:name], "can't be blank"
  end

  def test_field_auto_presence_nil
    form_class = build_form do
      field :name, :string
    end

    form = form_class.new
    assert form.invalid?
    assert_includes form.errors[:name], "can't be blank"
  end

  def test_field_auto_presence_valid
    form_class = build_form do
      field :name, :string
    end

    form = form_class.new(name: "Alice")
    assert form.valid?
  end

  def test_field_auto_presence_deduplicates_with_explicit
    form_class = build_form do
      field :name, :string
      validates :name, presence: true
    end

    form = form_class.new(name: "")
    form.valid?
    # Only one "can't be blank" error, not two
    assert_equal 1, form.errors[:name].count { |m| m == "can't be blank" }
  end

  def test_field_boolean_with_explicit_presence_still_accepts_false
    form_class = build_form do
      field :active, :boolean
      validates :active, presence: true
    end

    form = form_class.new(active: false)
    assert form.valid?, "false should be valid for boolean fields even with explicit presence validator"
  end

  def test_field_optional_boolean_with_explicit_presence_still_accepts_false
    form_class = build_form do
      field? :active, :boolean
      validates :active, presence: true
    end

    form = form_class.new(active: false)
    assert form.valid?, "false should be valid for optional boolean fields with explicit presence validator"
  end

  def test_field_boolean_required_accepts_false
    form_class = build_form do
      field :active, :boolean
    end

    form = form_class.new(active: false)
    assert form.valid?
  end

  def test_field_boolean_required_rejects_nil
    form_class = build_form do
      field :active, :boolean
    end

    form = form_class.new(active: nil)
    assert form.invalid?
    assert form.errors[:active].any?
  end

  def test_field_integer_required_accepts_zero
    form_class = build_form do
      field :count, :integer
    end

    form = form_class.new(count: 0)
    assert form.valid?
  end

  # --- field? (optional) ---

  def test_field_optional_allows_nil
    form_class = build_form do
      field? :notes, :string
    end

    form = form_class.new
    assert form.valid?
    assert_nil form.notes
  end

  def test_field_optional_allows_blank
    form_class = build_form do
      field? :notes, :string
    end

    form = form_class.new(notes: "")
    assert form.valid?
  end

  def test_field_optional_with_value
    form_class = build_form do
      field? :notes, :string
    end

    form = form_class.new(notes: "hello")
    assert_equal "hello", form.notes
  end

  def test_field_optional_tracks_as_not_required
    form_class = build_form do
      field? :notes, :string
    end

    field_def = form_class._field_registry[:notes]
    refute field_def.required
  end

  def test_field_optional_with_explicit_default
    form_class = build_form do
      field? :priority, :integer, default: 0
    end

    form = form_class.new
    assert_equal 0, form.priority
  end

  def test_field_optional_nil_default_when_unspecified
    form_class = build_form do
      field? :notes, :string
    end

    form = form_class.new
    assert_nil form.notes
  end

  # --- Registry tracking ---

  def test_field_registry
    form_class = build_form do
      field :name, :string
      field :email, :string, desc: "Email"
      field? :notes, :string
    end

    registry = form_class._field_registry
    assert_equal 3, registry.size
    assert_equal :string, registry[:name].type
    assert_equal "Email", registry[:email].desc
    refute registry[:notes].required
  end

  def test_required_fields
    form_class = build_form do
      field :name, :string
      field :email, :string
      field? :notes, :string
    end

    assert_equal %i[name email], form_class._required_fields
  end

  def test_raw_attribute_not_in_field_registry
    form_class = build_form do
      field :name, :string
      attribute :raw_attr, :string
    end

    assert form_class._field_registry.key?(:name)
    refute form_class._field_registry.key?(:raw_attr)
  end

  # --- Inheritance ---

  def test_child_inherits_field_registry
    parent = build_form do
      field :name, :string
    end

    child = build_form(parent: parent) do
      field :email, :string
    end

    assert_equal 2, child._field_registry.size
    assert child._field_registry.key?(:name)
    assert child._field_registry.key?(:email)
  end

  def test_parent_unaffected_by_child_fields
    parent = build_form do
      field :name, :string
    end

    build_form(parent: parent) do
      field :email, :string
    end

    assert_equal 1, parent._field_registry.size
  end

  # --- FieldDef ---

  def test_field_def_default_tracking
    form_class = build_form do
      field :name, :string
      field :currency, :string, default: "USD"
      field? :notes, :string
      field? :priority, :integer, default: 0
    end

    refute form_class._field_registry[:name].default?
    assert form_class._field_registry[:currency].default?
    assert_equal "USD", form_class._field_registry[:currency].default

    refute form_class._field_registry[:notes].default?
    assert form_class._field_registry[:priority].default?
    assert_equal 0, form_class._field_registry[:priority].default
  end

  # --- DSL validation ---

  def test_field_rejects_non_symbol_name
    err = assert_raises(ArgumentError) do
      build_form { field 123, :string }
    end
    assert_match(/field name must be a Symbol/, err.message)
  end

  def test_field_rejects_non_symbol_type
    err = assert_raises(ArgumentError) do
      build_form { field :name, "string" }
    end
    assert_match(/field type must be a Symbol/, err.message)
  end

  def test_field_rejects_non_string_desc
    err = assert_raises(ArgumentError) do
      build_form { field :name, :string, desc: 123 }
    end
    assert_match(/desc must be a String/, err.message)
  end

  def test_field_optional_rejects_non_symbol_name
    err = assert_raises(ArgumentError) do
      build_form { field? 123, :string }
    end
    assert_match(/field name must be a Symbol/, err.message)
  end

  # --- Coexistence with attribute ---

  def test_field_and_attribute_coexist
    form_class = build_form do
      field :name, :string
      attribute :raw_note, :string
    end

    form = form_class.new(name: "Alice", raw_note: "hi")
    assert_equal "Alice", form.name
    assert_equal "hi", form.raw_note
  end

  def test_to_h_includes_field_and_attribute_values
    form_class = build_form do
      field :name, :string
      attribute :raw_note, :string
    end

    form = form_class.new(name: "Alice", raw_note: "hi")
    h = form.to_h
    assert_equal "Alice", h[:name]
    assert_equal "hi", h[:raw_note]
  end

  # --- Nested forms with field ---

  def test_nested_form_uses_field
    form_class = build_form do
      field :name, :string

      nested_one :address do
        field :street, :string
        field :city, :string
        field? :apartment, :string
      end
    end

    form = form_class.new(name: "Alice", address: { street: "123 Main", city: "NYC" })
    assert form.valid?
    assert_equal "123 Main", form.address.street
  end

  def test_nested_form_field_validation
    form_class = build_form do
      field :name, :string

      nested_one :address do
        field :street, :string
        field :city, :string
      end
    end

    form = form_class.new(name: "Alice", address: { street: "", city: "" })
    assert form.invalid?
    assert form.errors[:"address.street"].any?
    assert form.errors[:"address.city"].any?
  end

  # --- Validation context ---

  def test_field_optional_with_contextual_presence
    form_class = build_form do
      field? :published_at, :datetime
      validates :published_at, presence: true, on: :publish
    end

    form = form_class.new
    assert form.valid?
    assert form.invalid?(:publish)
  end
end
