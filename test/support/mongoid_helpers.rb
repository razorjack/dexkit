# frozen_string_literal: true

module MongoidHelpers
  MONGOID_TEST_FLAG = "DEX_MONGOID_TESTS"
  MONGODB_URI_ENV = "DEX_MONGODB_URI"

  def setup_mongoid_operation_database
    _setup_mongoid!
    _ensure_mongoid_operation_models
    _ensure_mongoid_indexes(MongoOperationRecord)
    _clear_mongoid_collections(MongoOperationRecord, MinimalMongoOperationRecord, MongoTestModel)
  end

  def setup_mongoid_query_database
    _setup_mongoid!
    _ensure_mongoid_query_models
    _ensure_mongoid_indexes(MongoQueryUser)
    _clear_mongoid_collections(MongoQueryUser)
  end

  def setup_mongoid_event_database
    _setup_mongoid!
    _ensure_mongoid_event_models
    _clear_mongoid_collections(MongoEventStoreRecord)
  end

  private

  def _setup_mongoid!
    skip "Mongoid tests are disabled (set #{MONGOID_TEST_FLAG}=1)." unless ENV[MONGOID_TEST_FLAG] == "1"

    _configure_mongoid!
    _silence_mongoid_warnings { Mongoid.default_client.database.command(ping: 1) }
  rescue LoadError => e
    skip "Mongoid gem is unavailable: #{e.message}"
  rescue => e
    skip "MongoDB is unavailable: #{e.class}: #{e.message}"
  end

  def _configure_mongoid!
    return if MongoidHelpers.instance_variable_defined?(:@_configured) && MongoidHelpers.instance_variable_get(:@_configured)

    require "logger"

    _silence_mongoid_warnings do
      require "mongoid"

      Mongoid::Config.load_configuration(
        clients: {
          default: {
            uri: ENV.fetch(MONGODB_URI_ENV, "mongodb://127.0.0.1:27017/dexkit_test_#{Process.pid}")
          }
        },
        options: { raise_not_found_error: true }
      )

      Mongo::Logger.logger.level = Logger::ERROR if defined?(Mongo::Logger)
      Mongoid.default_client # eagerly initialize client (triggers URI parsing)
    end
    MongoidHelpers.instance_variable_set(:@_configured, true)
  end

  def _clear_mongoid_collections(*models)
    models.each(&:delete_all)
  end

  def _ensure_mongoid_indexes(*models)
    models.each do |model|
      model.create_indexes if model.respond_to?(:create_indexes)
    end
  end

  def _silence_mongoid_warnings
    old_verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = old_verbose
  end

  def _ensure_mongoid_operation_models
    _silence_mongoid_warnings do
      unless defined?(MongoOperationRecord)
        Object.const_set(:MongoOperationRecord, Class.new do
          include Mongoid::Document
          include Mongoid::Timestamps

          store_in collection: "mongo_operation_records"

          field :_id, type: String, default: -> { Dex::Id.generate("op_") }
          field :name, type: String
          field :trace_id, type: String
          field :actor_type, type: String
          field :actor_id, type: String
          field :trace, type: Array
          field :params, type: Hash
          field :result, type: Object
          field :status, type: String
          field :error_code, type: String
          field :error_message, type: String
          field :error_details, type: Hash
          field :once_key, type: String
          field :once_key_expires_at, type: Time
          field :performed_at, type: Time

          index({ once_key: 1 }, { unique: true, sparse: true })
        end)
      end

      unless defined?(MinimalMongoOperationRecord)
        Object.const_set(:MinimalMongoOperationRecord, Class.new do
          include Mongoid::Document
          include Mongoid::Timestamps

          store_in collection: "minimal_mongo_operation_records"

          field :_id, type: String, default: -> { Dex::Id.generate("op_") }
          field :name, type: String
        end)
      end

      unless defined?(MongoTestModel)
        Object.const_set(:MongoTestModel, Class.new do
          include Mongoid::Document
          include Mongoid::Timestamps

          store_in collection: "mongo_test_models"

          field :name, type: String
        end)
      end
    end
  end

  def _ensure_mongoid_query_models
    return if defined?(MongoQueryUser)

    _silence_mongoid_warnings do
      Object.const_set(:MongoQueryUser, Class.new do
        include Mongoid::Document
        include Mongoid::Timestamps

        store_in collection: "mongo_query_users"

        field :name, type: String
        field :email, type: String
        field :role, type: String
        field :age, type: Integer
        field :status, type: String
      end)
    end
  end

  def _ensure_mongoid_event_models
    return if defined?(MongoEventStoreRecord)

    _silence_mongoid_warnings do
      Object.const_set(:MongoEventStoreRecord, Class.new do
        include Mongoid::Document
        include Mongoid::Timestamps

        store_in collection: "mongo_event_store_records"

        field :_id, type: String
        field :trace_id, type: String
        field :actor_type, type: String
        field :actor_id, type: String
        field :trace, type: Array
        field :event_type, type: String
        field :payload, type: Hash
        field :metadata, type: Hash
      end)
    end
  end
end
