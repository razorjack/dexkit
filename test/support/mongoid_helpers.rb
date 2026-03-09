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

  def mongoid_transactions_supported?
    hello = Mongoid.default_client.database.command(hello: 1).first
    !hello.fetch("setName", "").to_s.empty?
  rescue
    false
  end

  private

  def _setup_mongoid!
    skip "Mongoid tests are disabled (set #{MONGOID_TEST_FLAG}=1)." unless ENV[MONGOID_TEST_FLAG] == "1"

    _configure_mongoid!
    Mongoid.default_client.database.command(ping: 1)
  rescue LoadError => e
    skip "Mongoid gem is unavailable: #{e.message}"
  rescue => e
    skip "MongoDB is unavailable: #{e.class}: #{e.message}"
  end

  def _configure_mongoid!
    return if defined?(@_mongoid_configured) && @_mongoid_configured

    require "logger"
    require "mongoid"

    Mongoid::Config.load_configuration(
      clients: {
        default: {
          uri: ENV.fetch(MONGODB_URI_ENV, "mongodb://127.0.0.1:27017/dexkit_test_#{Process.pid}?replicaSet=rs0")
        }
      },
      options: { raise_not_found_error: true }
    )

    Mongo::Logger.logger.level = Logger::ERROR if defined?(Mongo::Logger)
    @_mongoid_configured = true
  end

  def _clear_mongoid_collections(*models)
    models.each(&:delete_all)
  end

  def _ensure_mongoid_indexes(*models)
    models.each do |model|
      model.create_indexes if model.respond_to?(:create_indexes)
    end
  end

  def _ensure_mongoid_operation_models
    unless defined?(MongoOperationRecord)
      Object.const_set(:MongoOperationRecord, Class.new do
        include Mongoid::Document
        include Mongoid::Timestamps

        store_in collection: "mongo_operation_records"

        field :name, type: String
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

  def _ensure_mongoid_query_models
    return if defined?(MongoQueryUser)

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
