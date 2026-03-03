# frozen_string_literal: true

require "test_helper"

class TestFormNormalization < Minitest::Test
  def test_normalizes_on_assignment
    form_class = build_form do
      attribute :email, :string
      normalizes :email, with: -> { _1&.strip&.downcase.presence }
    end

    form = form_class.new(email: "  ALICE@EXAMPLE.COM  ")
    assert_equal "alice@example.com", form.email
  end

  def test_normalizes_nil_handling
    form_class = build_form do
      attribute :email, :string
      normalizes :email, with: -> { _1&.strip&.downcase.presence }
    end

    form = form_class.new(email: nil)
    assert_nil form.email
  end

  def test_normalizes_blank_to_nil
    form_class = build_form do
      attribute :email, :string
      normalizes :email, with: -> { _1&.strip.presence }
    end

    form = form_class.new(email: "   ")
    assert_nil form.email
  end

  def test_normalizes_on_reassignment
    form_class = build_form do
      attribute :email, :string
      normalizes :email, with: -> { _1&.strip&.downcase.presence }
    end

    form = form_class.new(email: "alice@example.com")
    form.email = "  BOB@EXAMPLE.COM  "
    assert_equal "bob@example.com", form.email
  end

  def test_normalizes_multiple_attributes
    form_class = build_form do
      attribute :email, :string
      attribute :name, :string
      normalizes :email, :name, with: -> { _1&.strip.presence }
    end

    form = form_class.new(email: "  alice@example.com  ", name: "  Alice  ")
    assert_equal "alice@example.com", form.email
    assert_equal "Alice", form.name
  end
end
