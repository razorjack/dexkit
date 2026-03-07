# frozen_string_literal: true

require "test_helper"

class TestEventAmbientContext < Minitest::Test
  # Context captured at publish time

  def test_event_prop_filled_from_context
    event_class = build_event do
      prop :user, String
      context user: :current_user
    end

    event = Dex.with_context(current_user: "alice") { event_class.new }
    assert_equal "alice", event.user
  end

  def test_explicit_kwarg_wins_over_context
    event_class = build_event do
      prop :user, String
      context user: :current_user
    end

    event = Dex.with_context(current_user: "alice") { event_class.new(user: "bob") }
    assert_equal "bob", event.user
  end

  def test_class_publish_with_context
    event_class = build_event do
      prop :order_id, Integer
      prop :user, String
      context user: :current_user
    end

    received = []
    build_handler do
      on event_class
      define_method(:perform) { received << event }
    end

    Dex.with_context(current_user: "alice") do
      event_class.publish(order_id: 1, sync: true)
    end

    assert_equal 1, received.size
    assert_equal "alice", received.first.user
    assert_equal 1, received.first.order_id
  end

  def test_event_works_without_context
    event_class = build_event do
      prop :user, String
      context user: :current_user
    end

    event = event_class.new(user: "explicit")
    assert_equal "explicit", event.user
  end

  def test_required_prop_raises_when_no_context_and_no_kwarg
    event_class = build_event do
      prop :user, String
      context user: :current_user
    end

    assert_raises(ArgumentError) { event_class.new }
  end

  # Identity shorthand

  def test_identity_shorthand
    event_class = build_event do
      prop :locale, Symbol
      context :locale
    end

    event = Dex.with_context(locale: :fr) { event_class.new }
    assert_equal :fr, event.locale
  end

  # Optional props

  def test_optional_prop_nil_when_no_context
    event_class = build_event do
      prop :order_id, Integer
      prop? :tenant, String
      context tenant: :current_tenant
    end

    event = event_class.new(order_id: 1)
    assert_nil event.tenant
  end

  def test_optional_prop_filled_from_context
    event_class = build_event do
      prop :order_id, Integer
      prop? :tenant, String
      context tenant: :current_tenant
    end

    event = Dex.with_context(current_tenant: "acme") { event_class.new(order_id: 1) }
    assert_equal "acme", event.tenant
  end

  # Introspection

  def test_context_mappings
    event_class = build_event do
      prop :user, String
      prop :locale, Symbol
      context user: :current_user
      context :locale
    end

    assert_equal({ user: :current_user, locale: :locale }, event_class.context_mappings)
  end

  # Inheritance

  def test_child_inherits_parent_context
    parent = build_event do
      prop :user, String
      context user: :current_user
    end

    child = Class.new(parent)

    event = Dex.with_context(current_user: "alice") { child.new }
    assert_equal "alice", event.user
  end

  # DSL validation

  def test_context_referencing_undeclared_prop_raises
    err = assert_raises(ArgumentError) do
      build_event do
        context user: :current_user
      end
    end
    assert_match(/undeclared prop/, err.message)
  end

  # Event is self-contained after publish

  def test_context_captured_and_frozen_on_event
    event_class = build_event do
      prop :user, String
      context user: :current_user
    end

    received = []
    build_handler do
      on event_class
      define_method(:perform) { received << event }
    end

    Dex.with_context(current_user: "alice") do
      event_class.publish(sync: true)
    end

    assert_equal "alice", received.first.user
    assert_equal({}, Dex.context)
  end
end
