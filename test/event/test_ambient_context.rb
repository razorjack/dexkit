# frozen_string_literal: true

require "test_helper"

class TestEventAmbientContext < Minitest::Test
  def test_event_prop_filled_from_context_and_explicit_kwarg_wins
    event_class = build_event do
      prop :user, String
      context user: :current_user
    end

    # Fills from ambient context
    event = Dex.with_context(current_user: "alice") { event_class.new }
    assert_equal "alice", event.user

    # Explicit kwarg wins over context
    event = Dex.with_context(current_user: "alice") { event_class.new(user: "bob") }
    assert_equal "bob", event.user
  end

  def test_child_inherits_parent_context
    parent = build_event do
      prop :user, String
      context user: :current_user
    end

    child = Class.new(parent)

    event = Dex.with_context(current_user: "alice") { child.new }
    assert_equal "alice", event.user
  end

  def test_context_referencing_undeclared_prop_raises
    err = assert_raises(ArgumentError) do
      build_event do
        context user: :current_user
      end
    end
    assert_match(/undeclared prop/, err.message)
  end

  def test_context_mappings
    event_class = build_event do
      prop :user, String
      prop :locale, Symbol
      context user: :current_user
      context :locale
    end

    assert_equal({ user: :current_user, locale: :locale }, event_class.context_mappings)
  end
end
