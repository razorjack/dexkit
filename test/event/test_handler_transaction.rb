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

  def test_after_commit_defers_with_and_without_transaction
    log = []
    event_class = build_event { prop :name, String }

    # With transaction enabled
    build_handler do
      on event_class
      transaction
      define_method(:perform) do
        after_commit { log << :committed_tx }
        log << :perform_tx
      end
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[perform_tx committed_tx], log

    # Without transaction (default for handler)
    log.clear
    Dex::Event::Bus.clear!

    build_handler do
      on event_class
      define_method(:perform) do
        after_commit { log << :committed_no_tx }
        log << :perform_no_tx
      end
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[perform_no_tx committed_no_tx], log
  end

  def test_transaction_default_disabled_for_handler
    settings = Dex::Event::Handler.settings_for(:transaction)
    assert_equal false, settings[:enabled]

    handler = build_handler { transaction false }
    assert_equal false, handler.settings_for(:transaction)[:enabled]
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
