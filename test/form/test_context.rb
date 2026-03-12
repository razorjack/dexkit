# frozen_string_literal: true

require "test_helper"

class TestFormContext < Minitest::Test
  # Basic context resolution

  def test_context_fills_field_from_ambient
    form_class = build_form do
      field :locale, :string
      context :locale
    end

    form = Dex.with_context(locale: "en") { form_class.new }
    assert_equal "en", form.locale
  end

  def test_explicit_value_wins_over_context
    form_class = build_form do
      field :locale, :string
      context :locale
    end

    form = Dex.with_context(locale: "en") { form_class.new(locale: "fr") }
    assert_equal "fr", form.locale
  end

  def test_works_without_ambient_context
    form_class = build_form do
      field? :locale, :string
      context :locale
    end

    form = form_class.new
    assert_nil form.locale
  end

  def test_explicit_mapping
    form_class = build_form do
      field :currency, :string
      context currency: :default_currency
    end

    form = Dex.with_context(default_currency: "EUR") { form_class.new }
    assert_equal "EUR", form.currency
  end

  # Mixed forms

  def test_mixed_shorthand_and_mapping
    form_class = build_form do
      field :locale, :string
      field :currency, :string
      context :locale, currency: :default_currency
    end

    form = Dex.with_context(locale: "en", default_currency: "USD") { form_class.new }
    assert_equal "en", form.locale
    assert_equal "USD", form.currency
  end

  # Multiple calls (additive)

  def test_multiple_context_calls_are_additive
    form_class = build_form do
      field :locale, :string
      field :currency, :string
      context :locale
      context currency: :default_currency
    end

    form = Dex.with_context(locale: "en", default_currency: "EUR") { form_class.new }
    assert_equal "en", form.locale
    assert_equal "EUR", form.currency
  end

  # Optional fields

  def test_optional_field_nil_when_no_context
    form_class = build_form do
      field? :tenant, :string
      context tenant: :current_tenant
    end

    form = form_class.new
    assert_nil form.tenant
  end

  def test_optional_field_filled_from_context
    form_class = build_form do
      field? :tenant, :string
      context tenant: :current_tenant
    end

    form = Dex.with_context(current_tenant: "acme") { form_class.new }
    assert_equal "acme", form.tenant
  end

  def test_absent_context_key_falls_through_to_default
    form_class = build_form do
      field? :tenant, :string, default: "fallback"
      context tenant: :current_tenant
    end

    form = Dex.with_context(locale: "en") { form_class.new }
    assert_equal "fallback", form.tenant
  end

  # String key handling

  def test_context_with_string_keys
    form_class = build_form do
      field :locale, :string
      context :locale
    end

    form = Dex.with_context(locale: "en") { form_class.new("locale" => "fr") }
    assert_equal "fr", form.locale
  end

  # Introspection

  def test_context_mappings
    form_class = build_form do
      field :locale, :string
      field :currency, :string
      context :locale, currency: :default_currency
    end

    assert_equal({ locale: :locale, currency: :default_currency }, form_class.context_mappings)
  end

  def test_context_mappings_empty_by_default
    form_class = build_form do
      field :name, :string
    end
    assert_equal({}, form_class.context_mappings)
  end

  # Inheritance

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

  def test_child_extends_parent_context
    parent = build_form do
      field :locale, :string
      context :locale
    end

    child = build_form(parent: parent) do
      field :currency, :string
      context currency: :default_currency
    end

    form = Dex.with_context(locale: "en", default_currency: "USD") { child.new }
    assert_equal "en", form.locale
    assert_equal "USD", form.currency
  end

  def test_parent_unaffected_by_child_context
    parent = build_form do
      field :locale, :string
      context :locale
    end

    build_form(parent: parent) do
      field :currency, :string
      context currency: :default_currency
    end

    assert_equal({ locale: :locale }, parent.context_mappings)
  end

  # Nested context

  def test_nested_context_merges
    form_class = build_form do
      field :locale, :string
      context :locale
    end

    form = Dex.with_context(locale: "en") do
      Dex.with_context(locale: "fr") do
        form_class.new
      end
    end

    assert_equal "fr", form.locale
  end

  # DSL validation

  def test_context_referencing_undeclared_field_raises
    err = assert_raises(ArgumentError) do
      build_form do
        context locale: :current_locale
      end
    end
    assert_match(/undeclared field/, err.message)
  end

  def test_context_shorthand_must_be_symbol
    err = assert_raises(ArgumentError) do
      build_form do
        field :locale, :string
        context "locale"
      end
    end
    assert_match(/must be a Symbol/, err.message)
  end

  def test_context_with_no_arguments_raises
    err = assert_raises(ArgumentError) do
      build_form { context }
    end
    assert_match(/requires at least one/, err.message)
  end

  def test_context_mapping_value_must_be_symbol
    err = assert_raises(ArgumentError) do
      build_form do
        field :locale, :string
        context locale: "current_locale"
      end
    end
    assert_match(/context key must be a Symbol/, err.message)
  end

  # Works with raw attribute too

  def test_context_works_with_raw_attribute
    form_class = build_form do
      attribute :locale, :string
      context :locale
    end

    form = Dex.with_context(locale: "en") { form_class.new }
    assert_equal "en", form.locale
  end
end
