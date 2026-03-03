# frozen_string_literal: true

require "test_helper"
require "action_controller"

class TestFormRailsCompat < Minitest::Test
  def test_nested_one_with_action_controller_parameters
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
        attribute :city, :string
      end
    end

    params = ActionController::Parameters.new(street: "123 Main", city: "NYC").permit(:street, :city)
    form = form_class.new(address: params)
    assert_equal "123 Main", form.address.street
    assert_equal "NYC", form.address.city
  end

  def test_nested_many_with_action_controller_parameters
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    params = ActionController::Parameters.new(
      "0" => { doc_type: "passport" },
      "1" => { doc_type: "visa" }
    ).permit!
    form = form_class.new(documents: params)
    assert_equal 2, form.documents.size
    assert_equal "passport", form.documents[0].doc_type
    assert_equal "visa", form.documents[1].doc_type
  end

  def test_nested_many_items_as_parameters
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    items = [
      ActionController::Parameters.new(doc_type: "passport").permit(:doc_type),
      ActionController::Parameters.new(doc_type: "visa").permit(:doc_type)
    ]
    form = form_class.new(documents: items)
    assert_equal 2, form.documents.size
    assert_equal "visa", form.documents[1].doc_type
  end

  def test_full_form_with_permitted_params
    form_class = build_form do
      attribute :email, :string
      validates :email, presence: true

      nested_one :address do
        attribute :street, :string
        attribute :city, :string
        validates :street, :city, presence: true
      end

      nested_many :documents do
        attribute :doc_type, :string
        validates :doc_type, presence: true
      end
    end

    params = ActionController::Parameters.new(
      email: "alice@example.com",
      address: { street: "123 Main", city: "NYC" },
      documents: [{ doc_type: "passport" }, { doc_type: "visa" }]
    ).permit(:email, address: %i[street city], documents: [:doc_type])

    form = form_class.new(params)
    assert form.valid?
    assert_equal "alice@example.com", form.email
    assert_equal "123 Main", form.address.street
    assert_equal 2, form.documents.size
  end

  def test_address_attributes_setter
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
        attribute :city, :string
      end
    end

    form = form_class.new
    form.address_attributes = { street: "123 Main", city: "NYC" }
    assert_equal "123 Main", form.address.street
    assert_equal "NYC", form.address.city
  end

  def test_documents_attributes_setter_with_numbered_hash
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new
    form.documents_attributes = { "0" => { doc_type: "passport" }, "1" => { doc_type: "visa" } }
    assert_equal 2, form.documents.size
    assert_equal "passport", form.documents[0].doc_type
    assert_equal "visa", form.documents[1].doc_type
  end

  def test_destroy_filtering_via_attributes_setter
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new
    form.documents_attributes = {
      "0" => { doc_type: "passport" },
      "1" => { :doc_type => "visa", "_destroy" => "1" }
    }
    assert_equal 1, form.documents.size
    assert_equal "passport", form.documents[0].doc_type
  end

  def test_string_keys_in_nested
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new("address" => { "street" => "123 Main" })
    assert_equal "123 Main", form.address.street
  end

  def test_nested_responds_to_model_name
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new
    assert_respond_to form.address, :model_name
  end

  def test_nested_responds_to_persisted
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
      end
    end

    form = form_class.new
    refute form.address.persisted?
  end

  def test_nested_many_items_respond_to_persisted
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    form = form_class.new(documents: [{ doc_type: "passport" }])
    refute form.documents[0].persisted?
  end

  def test_unpermitted_params_accepted_at_top_level
    form_class = build_form do
      attribute :email, :string
      attribute :name, :string
    end

    params = ActionController::Parameters.new(email: "alice@example.com", name: "Alice")
    form = form_class.new(params)
    assert_equal "alice@example.com", form.email
    assert_equal "Alice", form.name
  end

  def test_unpermitted_params_drop_undeclared_attributes
    form_class = build_form do
      attribute :email, :string
    end

    params = ActionController::Parameters.new(email: "alice@example.com", admin: true, secret: "hack")
    form = form_class.new(params)
    assert_equal "alice@example.com", form.email
  end

  def test_unpermitted_params_in_nested_one
    form_class = build_form do
      nested_one :address do
        attribute :street, :string
        attribute :city, :string
      end
    end

    params = ActionController::Parameters.new(street: "123 Main", city: "NYC")
    form = form_class.new(address: params)
    assert_equal "123 Main", form.address.street
    assert_equal "NYC", form.address.city
  end

  def test_unpermitted_params_in_nested_many
    form_class = build_form do
      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    params = ActionController::Parameters.new(
      "0" => { doc_type: "passport" },
      "1" => { doc_type: "visa" }
    )
    form = form_class.new(documents: params)
    assert_equal 2, form.documents.size
    assert_equal "passport", form.documents[0].doc_type
  end

  def test_unpermitted_params_full_form
    form_class = build_form do
      attribute :email, :string

      nested_one :address do
        attribute :street, :string
      end

      nested_many :documents do
        attribute :doc_type, :string
      end
    end

    params = ActionController::Parameters.new(
      email: "alice@example.com",
      address: { street: "123 Main" },
      documents: [{ doc_type: "passport" }]
    )
    form = form_class.new(params)
    assert_equal "alice@example.com", form.email
    assert_equal "123 Main", form.address.street
    assert_equal 1, form.documents.size
  end

  def test_record_not_publicly_writable
    form_class = build_form do
      attribute :email, :string
    end

    form = form_class.new(email: "test")
    assert_raises(NoMethodError) { form.record = Object.new }
  end

  def test_garbage_record_from_params_is_discarded
    form_class = build_form do
      attribute :email, :string
    end

    params = ActionController::Parameters.new(email: "alice@example.com", record: "malicious")
    form = form_class.new(params)
    assert_nil form.record
    assert_equal "alice@example.com", form.email
    refute form.persisted?
  end

  def test_with_record_validates_argument
    form_class = build_form do
      attribute :email, :string
    end

    form = form_class.new(email: "test")
    assert_raises(ArgumentError) { form.with_record("not a record") }
  end

  def test_with_record_from_unpermitted_params
    form_class = build_form do
      attribute :email, :string
    end

    params = ActionController::Parameters.new(email: "alice@example.com")
    record = Struct.new(:persisted?) { def to_key = [1] }.new(true)

    form = form_class.new(params).with_record(record)
    assert_equal "alice@example.com", form.email
    assert form.persisted?
    assert_equal [1], form.to_key
  end

  def test_full_form_integration
    form_class = build_form do
      attribute :email, :string
      attribute :first_name, :string

      normalizes :email, with: -> { _1&.strip&.downcase.presence }
      validates :email, :first_name, presence: true

      nested_one :address do
        attribute :street, :string
        attribute :city, :string
        validates :street, :city, presence: true
      end

      nested_many :documents do
        attribute :document_type, :string
        attribute :document_number, :string
        validates :document_type, :document_number, presence: true
      end
    end

    form = form_class.new(
      email: "  ALICE@EXAMPLE.COM  ",
      first_name: "Alice",
      address: { street: "123 Main", city: "NYC" },
      documents: [
        { document_type: "passport", document_number: "AB123" },
        { document_type: "visa", document_number: "CD456" }
      ]
    )

    assert form.valid?
    assert_equal "alice@example.com", form.email
    assert_equal "Alice", form.first_name
    assert_equal "123 Main", form.address.street
    assert_equal 2, form.documents.size

    h = form.to_h
    assert_equal "alice@example.com", h[:email]
    assert_equal({ street: "123 Main", city: "NYC" }, h[:address])
    assert_equal 2, h[:documents].size
  end
end
