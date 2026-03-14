# frozen_string_literal: true

require "test_helper"

class TestFormContext < Minitest::Test
  def test_ambient_fills_field_and_explicit_wins
    form_class = build_form do
      field :locale, :string
      context :locale
    end

    form = Dex.with_context(locale: "en") { form_class.new }
    assert_equal "en", form.locale

    form = Dex.with_context(locale: "en") { form_class.new(locale: "fr") }
    assert_equal "fr", form.locale
  end

  def test_identity_shorthand
    form_class = build_form do
      field :currency, :string
      context currency: :default_currency
    end

    form = Dex.with_context(default_currency: "EUR") { form_class.new }
    assert_equal "EUR", form.currency
  end

  def test_child_inherits_parent_context
    parent = build_form do
      field :locale, :string
      context :locale
    end

    child = build_form(parent: parent) do
      field :name, :string
    end

    form = Dex.with_context(locale: "en") { child.new(name: "Alice") }
    assert_equal "en", form.locale
  end

  def test_context_referencing_undeclared_field_raises
    err = assert_raises(ArgumentError) do
      build_form do
        context locale: :current_locale
      end
    end
    assert_match(/undeclared field/, err.message)
  end
end
