# frozen_string_literal: true

require "test_helper"

class TestEventHandlerTransaction < Minitest::Test
  def setup
    setup_test_database
  end

  def test_transaction_dsl_enables_wrapping
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      transaction
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal [:perform], log
  end

  def test_after_commit_defers_until_handler_completes
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      transaction
      define_method(:perform) do
        after_commit { log << :committed }
        log << :perform
      end
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[perform committed], log
  end

  def test_after_commit_defers_without_transaction_too
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      define_method(:perform) do
        after_commit { log << :committed }
        log << :perform
      end
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[perform committed], log
  end

  def test_transaction_false_disables_wrapping
    handler = build_handler do
      transaction false
    end

    settings = handler.settings_for(:transaction)
    assert_equal false, settings[:enabled]
  end

  def test_transaction_default_disabled_for_handler
    settings = Dex::Event::Handler.settings_for(:transaction)
    assert_equal false, settings[:enabled]
  end

  def test_exception_rolls_back_after_commit
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      transaction
      define_method(:perform) do
        after_commit { log << :committed }
        raise "boom"
      end
    end

    assert_raises(RuntimeError) do
      event_class.new(name: "test").publish(sync: true)
    end
    assert_empty log
  end

  def test_callbacks_and_transaction_compose
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      transaction
      before { log << :before }
      after { log << :after }
      define_method(:perform) do
        after_commit { log << :committed }
        log << :perform
      end
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[before perform after committed], log
  end
end
