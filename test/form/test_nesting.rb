# frozen_string_literal: true

require "test_helper"

class TestFormNesting < Minitest::Test
  # --- nested_one ---

  def test_nested_one_creates_accessor
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new(address: { street: "123 Main" })
    assert_equal "123 Main", form.address.street
  end

  def test_nested_one_coerces_hash
    form_class = build_form do
      nested_one :address do
        attribute :city, :string
      end
    end

    form = form_class.new(address: { city: "NYC" })
    assert_kind_of Dex::Form, form.address
    assert_equal "NYC", form.address.city
  end

  def test_nested_one_accepts_form_instance
    form_class = build_form do
      nested_one :address do
        attribute :city, :string
      end
    end

    address = form_class::Address.new(city: "NYC")
    form = form_class.new
    form.address = address
    assert_equal "NYC", form.address.city
  end

  def test_nested_one_default_initialization
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new
    assert_kind_of Dex::Form, form.address
    assert_nil form.address.street
  end

  def test_nested_one_validates
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
        validates :street, presence: true
      end
    end

    form = form_class.new(address: { street: "" })
    assert form.invalid?
    assert_includes form.errors.full_messages.join, "street"
  end

  def test_nested_one_error_prefixing
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
        validates :street, presence: true
      end
    end

    form = form_class.new(address: { street: "" })
    form.valid?
    assert form.errors[:"address.street"].any?
  end

  def test_nested_one_build_method
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new
    form.build_address(street: "456 Oak")
    assert_equal "456 Oak", form.address.street
  end

  def test_nested_one_attributes_setter
    form_class = build_form do
      nested_one :address do
        attribute :city, :string
      end
    end

    form = form_class.new
    form.address_attributes = { city: "Boston" }
    assert_equal "Boston", form.address.city
  end

  def test_nested_one_sets_constant
    form_class = define_form(:TestNestedConstForm) do
      nested_one :address do
        attribute :street, :string
      end
    end

    assert form_class.const_defined?(:Address)
    assert form_class::Address < Dex::Form
  end

  def test_nested_one_custom_class_name
    form_class = build_form do
      nested_one :address, class_name: "HomeAddress" do
        attribute :street, :string
      end
    end

    assert form_class.const_defined?(:HomeAddress)
  end

  def test_nested_one_nil_assignment
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new
    form.address = nil
    assert_nil form.address
  end

  def test_nested_one_destroy_sets_nil
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new(address: { street: "123 Main", _destroy: "1" })
    assert_nil form.address
  end

  def test_nested_one_destroy_false_keeps_form
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new(address: { street: "123 Main", _destroy: "0" })
    assert_equal "123 Main", form.address.street
  end

  def test_nested_one_explicit_nil_in_constructor
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new(address: nil)
    assert_nil form.address
  end

  # --- nested_many ---

  def test_nested_many_creates_accessor
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: [{ doc_type: "passport" }])
    assert_equal 1, form.documents.size
    assert_equal "passport", form.documents[0].doc_type
  end

  def test_nested_many_coerces_array_of_hashes
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: [{ doc_type: "passport" }, { doc_type: "visa" }])
    assert_equal 2, form.documents.size
    assert form.documents.all? { |d| d.is_a?(Dex::Form) }
  end

  def test_nested_many_explicit_nil_defaults_to_empty_array
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: nil)
    assert_equal [], form.documents
  end

  def test_nested_many_hash_with_symbol_keys
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: { first: { doc_type: "passport" }, second: { doc_type: "visa" } })
    assert_equal 2, form.documents.size
  end

  def test_nested_many_rails_numbered_hash_format
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: { "0" => { doc_type: "passport" }, "1" => { doc_type: "visa" } })
    assert_equal 2, form.documents.size
    assert_equal "passport", form.documents[0].doc_type
    assert_equal "visa", form.documents[1].doc_type
  end

  def test_nested_many_destroy_handling
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: [
      { doc_type: "passport" },
      { doc_type: "visa", _destroy: "1" },
      { doc_type: "id_card" }
    ])
    assert_equal 2, form.documents.size
    assert_equal "passport", form.documents[0].doc_type
    assert_equal "id_card", form.documents[1].doc_type
  end

  def test_nested_many_destroy_with_true_boolean
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: [
      { doc_type: "passport", _destroy: true },
      { doc_type: "visa", _destroy: false }
    ])
    assert_equal 1, form.documents.size
    assert_equal "visa", form.documents[0].doc_type
  end

  def test_nested_many_destroy_with_string_key
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: [{ :doc_type => "passport", "_destroy" => "true" }])
    assert_equal 0, form.documents.size
  end

  def test_nested_many_default_empty_array
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new
    assert_equal [], form.documents
  end

  def test_nested_many_validates_each_item
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
        validates :doc_type, presence: true
      end
    end

    form = form_class.new(documents: [{ doc_type: "" }, { doc_type: "passport" }])
    assert form.invalid?
  end

  def test_nested_many_error_prefixing_with_index
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
        validates :doc_type, presence: true
      end
    end

    form = form_class.new(documents: [{ doc_type: "passport" }, { doc_type: "" }])
    form.valid?
    assert form.errors[:"documents[1].doc_type"].any?
  end

  def test_nested_many_build_method
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new
    form.build_document(doc_type: "passport")
    assert_equal 1, form.documents.size
    assert_equal "passport", form.documents[0].doc_type
  end

  def test_nested_many_attributes_setter
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new
    form.documents_attributes = { "0" => { doc_type: "passport" } }
    assert_equal 1, form.documents.size
  end

  # --- Inheritance ---

  def test_inheritance_does_not_leak_nested
    parent = define_form(:ParentForm) do
      nested_one :address do
        attribute :street, :string
      end
    end

    child = define_form(:ChildForm, parent: parent) do
      nested_one :contact do
        attribute :phone, :string
      end
    end

    assert parent._nested_ones.key?(:address)
    refute parent._nested_ones.key?(:contact)
    assert child._nested_ones.key?(:address)
    assert child._nested_ones.key?(:contact)
  end

  # --- Serialization ---

  def test_nested_one_to_h
    form_class = build_form do
      attribute :name, :string
      nested_one :address do
        attribute :street, :string
        attribute :city, :string
      end
    end

    form = form_class.new(name: "Alice", address: { street: "123 Main", city: "NYC" })
    h = form.to_h
    assert_equal "Alice", h[:name]
    assert_equal({ street: "123 Main", city: "NYC" }, h[:address])
  end

  def test_nested_many_to_h
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: [{ doc_type: "passport" }, { doc_type: "visa" }])
    h = form.to_h
    assert_equal [{ doc_type: "passport" }, { doc_type: "visa" }], h[:documents]
  end

  def test_nested_one_requires_block
    assert_raises(ArgumentError) do
      build_form do
        nested_one :address
      end
    end
  end

  def test_nested_many_requires_block
    assert_raises(ArgumentError) do
      build_form do
        nested_many :documents
      end
    end
  end

  # --- Type enforcement ---

  def test_nested_one_rejects_unrelated_form
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end

      nested_one :contact do
        attribute :phone, :string
      end
    end

    form = form_class.new
    contact = form.contact

    assert_raises(ArgumentError) { form.address = contact }
  end

  def test_nested_one_accepts_subclass
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    subclass = Class.new(form_class::Address)
    form = form_class.new
    form.address = subclass.new(street: "123 Main")
    assert_equal "123 Main", form.address.street
  end

  def test_nested_many_rejects_unrelated_form
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end

      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new
    assert_raises(ArgumentError) { form.documents = [form.address] }
  end

  # --- Dual key precedence ---

  def test_attributes_key_takes_precedence_over_direct_key
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new(address: { street: "Direct" }, address_attributes: { street: "Attributes" })
    assert_equal "Attributes", form.address.street
  end

  # --- Deep nesting ---

  def test_deeply_nested_forms
    form_class = build_form do
      attribute :name, :string
      validates :name, presence: true

      nested_one :address do
        attribute :city, :string
        validates :city, presence: true

        nested_one :coordinate do
          attribute :lat, :float
          attribute :lng, :float
          validates :lat, presence: true
        end
      end
    end

    form = form_class.new(
      name: "Alice",
      address: { city: "NYC", coordinate: { lat: 40.7, lng: -74.0 } }
    )
    assert form.valid?

    result = form.to_h
    assert_equal 40.7, result[:address][:coordinate][:lat]
  end

  def test_deeply_nested_validation_propagation
    form_class = build_form do
      nested_one :address do
        attribute :city, :string

        nested_one :coordinate do
          attribute :lat, :float
          validates :lat, presence: true
        end
      end
    end

    form = form_class.new(address: { city: "NYC", coordinate: { lat: nil } })
    assert form.invalid?
    assert form.errors[:"address.coordinate.lat"].any?
  end

  # --- Combined validation ---

  def test_combined_validation_propagation
    form_class = build_form do
      attribute :email, :string
      validates :email, presence: true

      nested_one :address do
        attribute :street, :string
        validates :street, presence: true
      end

      nested_many :documents do
        attribute :doc_type, :string
        validates :doc_type, presence: true
      end
    end

    form = form_class.new(email: "", address: { street: "" }, documents: [{ doc_type: "" }])
    assert form.invalid?
    assert form.errors[:email].any?
    assert form.errors[:"address.street"].any?
    assert form.errors[:"documents[0].doc_type"].any?
  end

  # --- Constant naming ---

  def test_nested_many_uses_singular_constant_name
    form_class = define_form(:ConstNamingForm) do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    assert form_class.const_defined?(:Document)
    assert form_class::Document < Dex::Form
  end
end
