# frozen_string_literal: true

module DatabaseHelpers
  # Sets up an in-memory SQLite database with necessary tables for testing
  # Creates tables for OperationRecord, MinimalOperationRecord, and TestModel
  def setup_test_database
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )

    ActiveRecord::Schema.define do
      suppress_messages do
        # Full operation record with all fields
        create_table :operation_records, id: :string, force: true do |t|
          t.string :name, null: false
          t.string :trace_id
          t.string :actor_type
          t.string :actor_id
          t.json :trace
          t.json :params
          t.json :result
          t.string :status, null: false
          t.string :error_code
          t.string :error_message
          t.json :error_details
          t.string :once_key
          t.datetime :once_key_expires_at
          t.datetime :performed_at
          t.timestamps

          t.index :once_key, unique: true
          t.index :trace_id
          t.index %i[actor_type actor_id]
        end

        # Minimal operation record (for testing optional fields)
        create_table :minimal_operation_records, id: :string, force: true do |t|
          t.string :name, null: false
          t.timestamps
        end

        # Operation record with once_key but no once_key_expires_at
        create_table :once_no_expiry_records, id: :string, force: true do |t|
          t.string :name, null: false
          t.string :trace_id
          t.string :actor_type
          t.string :actor_id
          t.json :trace
          t.string :status, null: false
          t.json :params
          t.json :result
          t.string :once_key
          t.datetime :performed_at
          t.timestamps

          t.index :once_key, unique: true
        end

        # Test model for transaction tests
        create_table :test_models, force: true do |t|
          t.string :name, null: false
          t.timestamps
        end
      end
    end

    # Define ActiveRecord models (only if not already defined)
    unless defined?(OperationRecord)
      Object.const_set(:OperationRecord, Class.new(ActiveRecord::Base) do
        before_validation { self.id ||= Dex::Id.generate("op_") }
      end)
    end
    unless defined?(MinimalOperationRecord)
      Object.const_set(:MinimalOperationRecord, Class.new(ActiveRecord::Base) do
        before_validation { self.id ||= Dex::Id.generate("op_") }
      end)
    end
    unless defined?(OnceNoExpiryRecord)
      Object.const_set(:OnceNoExpiryRecord, Class.new(ActiveRecord::Base) do
        before_validation { self.id ||= Dex::Id.generate("op_") }
      end)
    end
    Object.const_set(:TestModel, Class.new(ActiveRecord::Base)) unless defined?(TestModel)
  end
end
