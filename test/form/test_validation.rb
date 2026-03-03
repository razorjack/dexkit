# frozen_string_literal: true

require "test_helper"

class TestFormValidation < Minitest::Test
  def test_validates_presence
    form_class = build_form do
      attribute :name, :string
      validates :name, presence: true
    end

    form = form_class.new(name: "")
    assert form.invalid?
    assert_includes form.errors[:name], "can't be blank"
  end

  def test_validates_format
    form_class = build_form do
      attribute :email, :string
      validates :email, format: { with: /@/ }
    end

    assert build_instance(form_class, email: "invalid").invalid?
    assert build_instance(form_class, email: "valid@test.com").valid?
  end

  def test_validates_length
    form_class = build_form do
      attribute :name, :string
      validates :name, length: { minimum: 2, maximum: 50 }
    end

    assert build_instance(form_class, name: "A").invalid?
    assert build_instance(form_class, name: "Alice").valid?
  end

  def test_validates_inclusion
    form_class = build_form do
      attribute :role, :string
      validates :role, inclusion: { in: %w[admin user] }
    end

    assert build_instance(form_class, role: "hacker").invalid?
    assert build_instance(form_class, role: "admin").valid?
  end

  def test_valid_returns_true_when_valid
    form_class = build_form do
      attribute :name, :string
      validates :name, presence: true
    end

    assert build_instance(form_class, name: "Alice").valid?
  end

  def test_errors_full_messages
    form_class = build_form do
      attribute :name, :string
      attribute :email, :string
      validates :name, :email, presence: true
    end

    form = form_class.new
    form.valid?
    assert_includes form.errors.full_messages, "Name can't be blank"
    assert_includes form.errors.full_messages, "Email can't be blank"
  end

  def test_validation_error
    form_class = build_form do
      attribute :name, :string
      validates :name, presence: true
    end

    form = form_class.new
    form.valid?
    error = Dex::Form::ValidationError.new(form)
    assert_equal form, error.form
    assert_match(/Name can't be blank/, error.message)
  end

  def test_validation_context
    form_class = build_form do
      attribute :name, :string
      validates :name, presence: true, on: :publish
    end

    form = form_class.new
    assert form.valid?
    assert form.invalid?(:publish)
  end

  def test_custom_validation_method
    form_class = build_form do
      attribute :start_date, :date
      attribute :end_date, :date

      validate :end_after_start

      define_method(:end_after_start) do
        return if start_date.blank? || end_date.blank?

        errors.add(:end_date, "must be after start date") if end_date <= start_date
      end
    end

    form = form_class.new(start_date: "2024-01-10", end_date: "2024-01-05")
    assert form.invalid?
    assert_includes form.errors[:end_date], "must be after start date"
  end

  private

  def build_instance(form_class, **attrs)
    form_class.new(attrs)
  end
end
