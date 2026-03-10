# frozen_string_literal: true

require_relative "support/test_helper"

class TestMongoidOnlyRuntimeWithoutActiveRecord < Minitest::Test
  QUERY_FIXTURES = [
    { name: "Alice", email: "alice@example.com", role: "admin", age: 30, status: "active" },
    { name: "Bob", email: "bob@example.com", role: "user", age: 25, status: "active" },
    { name: "Charlie", email: "charlie@example.com", role: "user", age: 35, status: "inactive" }
  ].freeze

  def setup
    setup_mongoid_operation_database
    setup_mongoid_query_database
    setup_mongoid_event_database

    Dex.configure do |config|
      config.record_class = MongoOperationRecord
      config.transaction_adapter = :mongoid
    end
    Dex.reset_record_backend!
  end

  def teardown
    Dex.configure do |config|
      config.record_class = nil
      config.transaction_adapter = nil
      config.event_store = nil
    end
    Dex.reset_record_backend!
    clear_enqueued_jobs
    clear_performed_jobs
    super
  end

  def test_active_record_is_not_loaded
    assert_nil defined?(ActiveRecord)
  end

  def test_async_record_job_round_trip_without_active_record
    with_mongoid_recording do
      op = define_operation(:MongoidOnlyAsyncRecordingOp) do
        prop :name, String

        def perform
          { greeting: "Hello #{name}" }
        end
      end

      perform_enqueued_jobs do
        op.new(name: "Ada").async.call
      end

      record = MongoOperationRecord.last
      assert_equal "MongoidOnlyAsyncRecordingOp", record.name
      assert_equal "completed", record.status
      assert_equal({ "name" => "Ada" }, normalize_hash(record.params))
      assert_equal({ "greeting" => "Hello Ada" }, normalize_hash(record.result))
      refute_nil record.performed_at
    end
  end

  def test_once_replays_result_without_active_record
    with_mongoid_recording do
      op = define_operation(:MongoidOnlyOnceReplay) do
        transaction false
        prop :order_id, Integer
        once :order_id

        def perform
          { order_id: order_id }
        end
      end

      first = op.new(order_id: 1).call
      second = op.new(order_id: 1).call

      assert_equal({ order_id: 1 }, first)
      assert_equal({ "order_id" => 1 }, second)
      assert_equal 1, MongoOperationRecord.where(once_key: "MongoidOnlyOnceReplay/order_id=1").count
    end
  end

  def test_query_filters_and_sorts_without_active_record
    seed_query_users

    query_class = Class.new(Dex::Query) do
      scope { MongoQueryUser.all }
      prop? :role, String
      filter :role
      sort :name
    end

    result = query_class.call(scope: MongoQueryUser.where(status: "active"), role: "user", sort: "name")

    assert_kind_of Mongoid::Criteria, result
    assert_equal ["Bob"], result.map(&:name)
  end

  def test_event_store_persists_to_mongoid_without_active_record
    event_class = define_event(:MongoidOnlyStoredEvent) do
      prop :name, String
    end

    Dex.configure { |config| config.event_store = MongoEventStoreRecord }

    event_class.new(name: "Ada").publish(sync: true)

    record = MongoEventStoreRecord.last
    assert_equal "MongoidOnlyStoredEvent", record.event_type
    assert_equal({ "name" => "Ada" }, normalize_hash(record.payload))
    assert_match(/\A[^[:space:]]+\z/, normalize_hash(record.metadata).fetch("id"))
    assert_match(/\A[^[:space:]]+\z/, normalize_hash(record.metadata).fetch("trace_id"))
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, normalize_hash(record.metadata).fetch("timestamp"))
  end

  def test_sync_handler_transaction_defers_after_commit_without_active_record
    skip "MongoDB replica set is required for Mongoid transaction tests." unless mongoid_transactions_supported?

    event_class = define_event(:MongoidOnlyRuntimeEvent) do
      prop :name, String
    end

    log = []

    define_handler(:MongoidOnlyRuntimeHandler) do
      on event_class
      transaction

      define_method(:perform) do
        MongoTestModel.create!(name: event.name)
        after_commit { log << :committed }
      end
    end

    event_class.new(name: "runtime").publish(sync: true)

    assert_equal [:committed], log
    assert_equal 1, MongoTestModel.where(name: "runtime").count
  end

  def test_async_handler_executes_without_active_record
    event_class = define_event(:MongoidOnlyAsyncEvent) do
      prop :name, String
    end

    define_handler(:MongoidOnlyAsyncHandler) do
      on event_class

      define_method(:perform) do
        MongoTestModel.create!(name: "async-#{event.name}")
      end
    end

    perform_enqueued_jobs do
      event_class.new(name: "ada").publish(sync: false)
    end

    assert_equal 1, MongoTestModel.where(name: "async-ada").count
  end

  def test_record_backend_validation_fails_fast_without_active_record
    with_mongoid_recording(record_class: MinimalMongoOperationRecord) do
      op = define_operation(:MongoidOnlyMisconfiguredRecordOp) do
        prop :name, String

        def perform
          nil
        end
      end

      error = assert_raises(ArgumentError) { op.new(name: "Ada").call }
      assert_match(/missing required attributes/, error.message)
      assert_match(/status/, error.message)
      assert_match(/performed_at/, error.message)
    end
  end

  def test_form_model_binding_delegates_to_mongoid_record_without_active_record
    form_class = define_form(:MongoidOnlyModelForm) do
      model MongoTestModel
      attribute :name, :string
    end

    record = MongoTestModel.create!(name: "Ada")
    form = form_class.new(name: "Ada", record: record)

    assert_equal MongoTestModel.model_name, form.model_name
    assert form.persisted?
    assert_equal record.to_key, form.to_key
    assert_equal record.to_param, form.to_param
  end

  private

  def with_mongoid_recording(record_class: MongoOperationRecord, &block)
    with_recording(record_class: record_class, &block)
  end

  def seed_query_users
    QUERY_FIXTURES.each { |attrs| MongoQueryUser.create!(attrs) }
  end

  def normalize_hash(value)
    return value unless value.is_a?(Hash)

    value.each_with_object({}) do |(key, nested_value), result|
      result[key.to_s] = normalize_hash(nested_value)
    end
  end
end
