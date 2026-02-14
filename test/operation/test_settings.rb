# frozen_string_literal: true

require "test_helper"

class TestOperationSettings < Minitest::Test
  def test_set_stores_settings
    op = build_operation do
      set :async, queue: "low"
    end

    assert_equal({queue: "low"}, op.settings_for(:async))
  end

  def test_set_merges_settings
    op = build_operation do
      set :async, queue: "low"
      set :async, priority: 5
    end

    assert_equal({queue: "low", priority: 5}, op.settings_for(:async))
  end

  def test_different_keys_are_independent
    op = build_operation do
      set :async, queue: "low"
      set :record, enabled: true
    end

    assert_equal({queue: "low"}, op.settings_for(:async))
    assert_equal({enabled: true}, op.settings_for(:record))
  end

  def test_unset_key_returns_empty_hash
    op = build_operation

    assert_equal({}, op.settings_for(:async))
  end

  def test_settings_inherit_from_parent
    parent = build_operation do
      set :async, queue: "default"
    end

    child = build_operation(parent: parent)

    assert_equal({queue: "default"}, child.settings_for(:async))
  end

  def test_child_settings_override_parent
    parent = build_operation do
      set :async, queue: "default", priority: 5
    end

    child = build_operation(parent: parent) do
      set :async, queue: "urgent"
    end

    assert_equal({queue: "urgent", priority: 5}, child.settings_for(:async))
  end
end
