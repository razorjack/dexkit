# frozen_string_literal: true

require "test_helper"

class TestActor < Minitest::Test
  # --- Dex.actor ---

  def test_actor_returns_nil_without_trace
    assert_nil Dex.actor
  end

  def test_actor_returns_nil_when_trace_has_no_actor
    Dex::Trace.start do
      assert_nil Dex.actor
    end
  end

  def test_actor_returns_reconstituted_hash
    Dex::Trace.start(actor: { type: :user, id: 42 }) do
      actor = Dex.actor

      assert_equal "user", actor[:type]
      assert_equal "42", actor[:id]
      refute actor.key?(:actor_type)
    end
  end

  def test_actor_preserves_extra_keys
    Dex::Trace.start(actor: { type: :admin, id: 5, on_behalf_of: 42 }) do
      actor = Dex.actor

      assert_equal "admin", actor[:type]
      assert_equal "5", actor[:id]
      assert_equal 42, actor[:on_behalf_of]
    end
  end

  def test_actor_returns_deep_copy
    Dex::Trace.start(actor: { type: :user, id: 1 }) do
      a = Dex.actor
      b = Dex.actor
      refute_same a, b
    end
  end

  # --- Dex.system ---

  def test_system_without_name
    h = Dex.system

    assert_equal({ type: :system }, h)
    assert h.frozen?
  end

  def test_system_with_name
    h = Dex.system("nightly_cleanup")

    assert_equal({ type: :system, name: "nightly_cleanup" }, h)
    assert h.frozen?
  end

  def test_system_with_symbol_name
    h = Dex.system(:reindex)

    assert_equal({ type: :system, name: "reindex" }, h)
  end

  def test_system_usable_as_actor
    Dex::Trace.start(actor: Dex.system("payroll")) do
      actor = Dex.actor

      assert_equal "system", actor[:type]
      assert_equal "payroll", actor[:name]
    end
  end
end
