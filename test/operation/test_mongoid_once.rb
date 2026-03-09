# frozen_string_literal: true

require "test_helper"

class TestOperationMongoidOnce < Minitest::Test
  def setup
    setup_mongoid_operation_database
    Dex.configure { |c| c.record_class = MongoOperationRecord }
    Dex.configure { |c| c.transaction_adapter = nil }
    Dex.reset_record_backend!
  end

  def teardown
    Dex.configure { |c| c.record_class = nil }
    Dex.configure { |c| c.transaction_adapter = nil }
    Dex.reset_record_backend!
    super
  end

  def test_once_replays_result_with_mongoid_record_backend
    op = define_operation(:MongoidOnceReplay) do
      transaction false
      prop :order_id, Integer
      once :order_id

      def perform
        MongoTestModel.create!(name: "order-#{order_id}")
        { order_id: order_id }
      end
    end

    first = op.new(order_id: 1).call
    second = op.new(order_id: 1).call

    assert_equal({ order_id: 1 }, first)
    assert_equal({ "order_id" => 1 }, second)
    assert_equal 1, MongoTestModel.where(name: "order-1").count
    assert_equal 1, MongoOperationRecord.where(once_key: "MongoidOnceReplay/order_id=1").count
  end

  def test_clear_once_allows_reexecution_with_mongoid_record_backend
    op = define_operation(:MongoidOnceClear) do
      transaction false
      prop :order_id, Integer
      once :order_id

      def perform
        MongoTestModel.create!(name: "order-#{order_id}")
      end
    end

    op.new(order_id: 7).call
    assert_equal "completed", MongoOperationRecord.where(once_key: "MongoidOnceClear/order_id=7").first.status
    op.clear_once!(order_id: 7)
    op.new(order_id: 7).call

    assert_equal 2, MongoTestModel.where(name: "order-7").count
  end
end
