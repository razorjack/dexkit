# frozen_string_literal: true

require "test_helper"

class TestOperationContext < Minitest::Test
  def setup
    setup_test_database
  end

  # Basic context resolution

  def test_context_fills_prop_from_ambient
    op = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    result = Dex.with_context(current_user: "alice") { op.call }
    assert_equal "alice", result
  end

  def test_explicit_kwarg_wins_over_context
    op = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    result = Dex.with_context(current_user: "alice") { op.call(user: "bob") }
    assert_equal "bob", result
  end

  def test_works_without_ambient_context
    op = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    assert_equal "explicit", op.call(user: "explicit")
  end

  def test_required_prop_raises_when_no_context_and_no_kwarg
    op = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    assert_raises(ArgumentError) { op.call }
  end

  # Identity shorthand

  def test_identity_shorthand
    op = build_operation do
      prop :locale, Symbol
      context :locale
      def perform = locale
    end

    result = Dex.with_context(locale: :fr) { op.call }
    assert_equal :fr, result
  end

  # Mixed forms

  def test_mixed_shorthand_and_mapping
    op = build_operation do
      prop :locale, Symbol
      prop :user, String
      context :locale, user: :current_user
      def perform = [locale, user]
    end

    result = Dex.with_context(locale: :en, current_user: "alice") { op.call }
    assert_equal [:en, "alice"], result
  end

  # Multiple calls (additive)

  def test_multiple_context_calls_are_additive
    op = build_operation do
      prop :user, String
      prop :locale, Symbol
      context user: :current_user
      context :locale
      def perform = [user, locale]
    end

    result = Dex.with_context(current_user: "alice", locale: :de) { op.call }
    assert_equal ["alice", :de], result
  end

  # Optional props

  def test_optional_prop_nil_when_no_context
    op = build_operation do
      prop? :tenant, String
      context tenant: :current_tenant
      def perform = tenant
    end

    assert_nil op.call
  end

  def test_optional_prop_filled_from_context
    op = build_operation do
      prop? :tenant, String
      context tenant: :current_tenant
      def perform = tenant
    end

    result = Dex.with_context(current_tenant: "acme") { op.call }
    assert_equal "acme", result
  end

  def test_explicit_nil_in_context_overrides_default
    op = build_operation do
      prop? :tenant, String, default: "fallback"
      context tenant: :current_tenant
      def perform = tenant
    end

    result = Dex.with_context(current_tenant: nil) { op.call }
    assert_nil result
  end

  def test_absent_context_key_falls_through_to_default
    op = build_operation do
      prop? :tenant, String, default: "fallback"
      context tenant: :current_tenant
      def perform = tenant
    end

    result = Dex.with_context(locale: :en) { op.call }
    assert_equal "fallback", result
  end

  # Nesting

  def test_nested_context_merges
    op = build_operation do
      prop :user, String
      prop :locale, Symbol
      context user: :current_user
      context :locale
      def perform = [user, locale]
    end

    result = Dex.with_context(current_user: "alice", locale: :en) do
      Dex.with_context(locale: :fr) do
        op.call
      end
    end

    assert_equal ["alice", :fr], result
  end

  def test_context_restores_after_nested_block
    outer = nil
    inner = nil

    Dex.with_context(locale: :en) do
      outer = Dex.context[:locale]
      Dex.with_context(locale: :fr) do
        inner = Dex.context[:locale]
      end
      assert_equal :en, Dex.context[:locale]
    end

    assert_equal :en, outer
    assert_equal :fr, inner
  end

  # Introspection

  def test_context_mappings
    op = build_operation do
      prop :user, String
      prop :locale, Symbol
      context user: :current_user
      context :locale
    end

    assert_equal({ user: :current_user, locale: :locale }, op.context_mappings)
  end

  def test_context_mappings_empty_by_default
    op = build_operation do
      def perform = "ok"
    end
    assert_equal({}, op.context_mappings)
  end

  # Inheritance

  def test_child_inherits_parent_context
    parent = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    child = build_operation(parent: parent)
    result = Dex.with_context(current_user: "alice") { child.call }
    assert_equal "alice", result
  end

  def test_child_extends_parent_context
    parent = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    child = build_operation(parent: parent) do
      prop :locale, Symbol
      context :locale
      def perform = [user, locale]
    end

    result = Dex.with_context(current_user: "alice", locale: :en) { child.call }
    assert_equal ["alice", :en], result
  end

  def test_parent_unaffected_by_child_context
    parent = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    build_operation(parent: parent) do
      prop :locale, Symbol
      context :locale
    end

    assert_equal({ user: :current_user }, parent.context_mappings)
  end

  # Guard integration

  def test_guards_access_context_resolved_props
    op = build_operation do
      prop :role, String
      context role: :current_role
      guard(:unauthorized) { role != "admin" }
      def perform = "ok"
    end

    assert_equal "ok", Dex.with_context(current_role: "admin") { op.call }
    assert_raises(Dex::Error) { Dex.with_context(current_role: "guest") { op.call } }
  end

  def test_callable_with_context
    op = build_operation do
      prop :role, String
      context role: :current_role
      guard(:unauthorized) { role != "admin" }
      def perform = "ok"
    end

    assert Dex.with_context(current_role: "admin") { op.callable? }
    refute Dex.with_context(current_role: "guest") { op.callable? }
  end

  def test_callable_explicit_kwarg_overrides_context
    op = build_operation do
      prop :role, String
      context role: :current_role
      guard(:unauthorized) { role != "admin" }
      def perform = "ok"
    end

    Dex.with_context(current_role: "guest") do
      assert op.callable?(role: "admin")
      refute op.callable?(role: "guest")
    end
  end

  # Safe mode integration

  def test_safe_mode_with_context
    op = build_operation do
      prop :user, String
      context user: :current_user
      error :denied
      def perform = error!(:denied)
    end

    result = Dex.with_context(current_user: "alice") { op.new.safe.call }
    assert result.error?
    assert_equal :denied, result.code
  end

  # DSL validation

  def test_context_referencing_undeclared_prop_raises
    err = assert_raises(ArgumentError) do
      build_operation do
        context user: :current_user
      end
    end
    assert_match(/undeclared prop/, err.message)
  end

  def test_context_shorthand_must_be_symbol
    err = assert_raises(ArgumentError) do
      build_operation do
        prop :locale, Symbol
        context "locale"
      end
    end
    assert_match(/must be a Symbol/, err.message)
  end

  def test_context_with_no_arguments_raises
    err = assert_raises(ArgumentError) do
      build_operation do
        context
      end
    end
    assert_match(/requires at least one/, err.message)
  end

  def test_context_mapping_value_must_be_symbol
    err = assert_raises(ArgumentError) do
      build_operation do
        prop :user, String
        context user: "current_user"
      end
    end
    assert_match(/context key must be a Symbol/, err.message)
  end

  # Dex.context / Dex.with_context

  def test_dex_context_empty_outside_block
    assert_equal({}, Dex.context)
  end

  def test_dex_context_available_inside_block
    Dex.with_context(current_user: "alice") do
      assert_equal({ current_user: "alice" }, Dex.context)
    end
  end

  def test_dex_context_cleaned_up_after_block
    Dex.with_context(current_user: "alice") { nil }
    assert_equal({}, Dex.context)
  end

  def test_dex_context_cleaned_up_on_exception
    begin
      Dex.with_context(current_user: "alice") { raise "boom" }
    rescue RuntimeError
      nil
    end
    assert_equal({}, Dex.context)
  end

  # Nested operations inherit context

  def test_nested_operation_inherits_context
    inner_op = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    outer_op = Class.new(Dex::Operation) do
      define_method(:perform) { inner_op.call }
    end

    result = Dex.with_context(current_user: "alice") { outer_op.call }
    assert_equal "alice", result
  end

  # Child remaps same prop to different context key

  def test_child_remaps_parent_context_key
    parent = build_operation do
      prop :user, String
      context user: :current_user
      def perform = user
    end

    child = build_operation(parent: parent) do
      context user: :acting_user
    end

    assert_equal({ user: :acting_user }, child.context_mappings)
    result = Dex.with_context(acting_user: "bob") { child.call }
    assert_equal "bob", result
  end

  # with_context returns block value

  def test_with_context_returns_block_value
    result = Dex.with_context(locale: :en) { 42 }
    assert_equal 42, result
  end
end
