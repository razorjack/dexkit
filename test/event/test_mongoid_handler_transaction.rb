# frozen_string_literal: true

require "test_helper"

class TestEventMongoidHandlerTransaction < Minitest::Test
  def setup
    setup_mongoid_operation_database
    skip "MongoDB replica set is required for Mongoid transaction tests." unless mongoid_transactions_supported?

    Dex.configure { |c| c.transaction_adapter = :mongoid }
  end

  def teardown
    Dex.configure { |c| c.transaction_adapter = nil }
    super
  end

  def test_handler_transaction_commits_and_defers_after_commit
    event_class = build_event do
      prop :name, String
    end

    log = []

    build_handler do
      on event_class
      transaction

      define_method(:perform) do
        MongoTestModel.create!(name: event.name)
        after_commit { log << :committed }
      end
    end

    event_class.new(name: "mongoid-handler").publish(sync: true)

    assert_equal [:committed], log
    assert_equal 1, MongoTestModel.where(name: "mongoid-handler").count
  end

  def test_handler_transaction_rolls_back_on_exception
    event_class = build_event do
      prop :name, String
    end

    build_handler do
      on event_class
      transaction

      define_method(:perform) do
        MongoTestModel.create!(name: event.name)
        raise "boom"
      end
    end

    assert_raises(RuntimeError) do
      event_class.new(name: "mongoid-handler").publish(sync: true)
    end

    assert_equal 0, MongoTestModel.where(name: "mongoid-handler").count
  end
end
