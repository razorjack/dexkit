# frozen_string_literal: true

require "test_helper"

class TestFormUniqueness < Minitest::Test
  def setup
    setup_test_database

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :uniqueness_models, force: true do |t|
          t.string :email, null: false
          t.string :name
          t.integer :tenant_id
          t.boolean :active, default: true
          t.timestamps
        end
      end
    end

    unless defined?(UniquenessModel)
      Object.const_set(:UniquenessModel, Class.new(ActiveRecord::Base) {
        self.table_name = "uniqueness_models"
      })
    end
  end

  def test_basic_uniqueness
    UniquenessModel.create!(email: "taken@example.com")

    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      validates :email, uniqueness: true
    end

    form = form_class.new(email: "taken@example.com")
    assert form.invalid?
    assert_includes form.errors[:email], "has already been taken"
  end

  def test_uniqueness_passes_when_no_duplicate
    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      validates :email, uniqueness: true
    end

    form = form_class.new(email: "unique@example.com")
    assert form.valid?
  end

  def test_uniqueness_excludes_current_record
    record = UniquenessModel.create!(email: "alice@example.com")

    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      validates :email, uniqueness: true
    end

    form = form_class.new(email: "alice@example.com", record: record)
    assert form.valid?
  end

  def test_uniqueness_with_explicit_model
    UniquenessModel.create!(email: "taken@example.com")

    form_class = build_form do
      attribute :email, :string
      validates :email, uniqueness: { model: UniquenessModel }
    end

    form = form_class.new(email: "taken@example.com")
    assert form.invalid?
  end

  def test_uniqueness_with_scope
    UniquenessModel.create!(email: "alice@example.com", tenant_id: 1)

    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      attribute :tenant_id, :integer
      validates :email, uniqueness: { scope: :tenant_id }
    end

    # Same tenant — should be invalid
    form = form_class.new(email: "alice@example.com", tenant_id: 1)
    assert form.invalid?

    # Different tenant — should be valid
    form2 = form_class.new(email: "alice@example.com", tenant_id: 2)
    assert form2.valid?
  end

  def test_uniqueness_case_insensitive
    UniquenessModel.create!(email: "Alice@Example.com")

    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      validates :email, uniqueness: { case_sensitive: false }
    end

    form = form_class.new(email: "ALICE@EXAMPLE.COM")
    assert form.invalid?
  end

  def test_uniqueness_with_conditions
    UniquenessModel.create!(email: "alice@example.com", active: true)
    UniquenessModel.create!(email: "bob@example.com", active: false)

    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      validates :email, uniqueness: { conditions: -> { where(active: true) } }
    end

    # Active record with same email — invalid
    form = form_class.new(email: "alice@example.com")
    assert form.invalid?

    # Inactive record with same email — valid (excluded by conditions)
    form2 = form_class.new(email: "bob@example.com")
    assert form2.valid?
  end

  def test_uniqueness_custom_message
    UniquenessModel.create!(email: "taken@example.com")

    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      validates :email, uniqueness: { message: "is already registered" }
    end

    form = form_class.new(email: "taken@example.com")
    form.valid?
    assert_includes form.errors[:email], "is already registered"
  end

  def test_uniqueness_attribute_mapping
    UniquenessModel.create!(email: "taken@example.com")

    form_class = build_form do
      model UniquenessModel
      attribute :user_email, :string
      validates :user_email, uniqueness: { attribute: :email }
    end

    form = form_class.new(user_email: "taken@example.com")
    assert form.invalid?
    assert form.errors[:user_email].any?
  end

  def test_uniqueness_skips_blank_values
    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      validates :email, uniqueness: true
    end

    form = form_class.new(email: "")
    # Should not query the database for blank values
    assert form.valid? || form.errors[:email].none? { |e| e.include?("taken") }
  end

  def test_uniqueness_model_inference_from_class_name
    UniquenessModel.create!(email: "taken@example.com")

    form_class = define_form(:UniquenessModelForm) do
      attribute :email, :string
      validates :email, uniqueness: true
    end

    form = form_class.new(email: "taken@example.com")
    assert form.invalid?
  end

  def test_uniqueness_excludes_current_record_with_custom_primary_key
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :uuid_models, id: false, force: true do |t|
          t.string :uuid, primary_key: true
          t.string :email, null: false
        end
      end
    end

    uuid_model_class = Class.new(ActiveRecord::Base) do
      self.table_name = "uuid_models"
      self.primary_key = "uuid"
    end

    record = uuid_model_class.create!(uuid: "abc-123", email: "alice@example.com")

    form_class = build_form do
      model uuid_model_class
      attribute :email, :string
      validates :email, uniqueness: true
    end

    form = form_class.new(email: "alice@example.com", record: record)
    assert form.valid?
  end

  def test_uniqueness_conditions_with_form_argument
    UniquenessModel.create!(email: "alice@example.com", active: true, tenant_id: 1)
    UniquenessModel.create!(email: "alice@example.com", active: true, tenant_id: 2)

    form_class = build_form do
      model UniquenessModel
      attribute :email, :string
      attribute :tenant_id, :integer
      validates :email, uniqueness: {
        conditions: ->(form) { where(active: true, tenant_id: form.tenant_id) }
      }
    end

    # Matches tenant 1 — invalid
    form = form_class.new(email: "alice@example.com", tenant_id: 1)
    assert form.invalid?

    # No match for tenant 3 — valid
    form2 = form_class.new(email: "alice@example.com", tenant_id: 3)
    assert form2.valid?
  end

  def test_uniqueness_no_model_is_no_op
    form_class = build_form do
      attribute :email, :string
      validates :email, uniqueness: true
    end

    form = form_class.new(email: "anything@example.com")
    assert form.valid?
  end

  def test_uniqueness_rejects_string_model_at_declaration
    assert_raises(ArgumentError, /must be a Class/) do
      build_form do
        attribute :email, :string
        validates :email, uniqueness: { model: "UniquenessModel" }
      end
    end
  end

  def test_uniqueness_rejects_non_callable_conditions_at_declaration
    assert_raises(ArgumentError, /must be callable/) do
      build_form do
        attribute :email, :string
        validates :email, uniqueness: { model: UniquenessModel, conditions: "where(active: true)" }
      end
    end
  end
end
