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
        create_table :operation_records, force: true do |t|
          t.string :name, null: false
          t.json :params, default: {}
          t.json :response
          t.string :status
          t.string :error
          t.datetime :performed_at
          t.timestamps
        end

        # Minimal operation record (for testing optional fields)
        create_table :minimal_operation_records, force: true do |t|
          t.string :name, null: false
          t.timestamps
        end

        # Test model for transaction tests
        create_table :test_models, force: true do |t|
          t.string :name, null: false
          t.timestamps
        end
      end
    end

    # Define ActiveRecord models (only if not already defined)
    Object.const_set(:OperationRecord, Class.new(ActiveRecord::Base)) unless defined?(OperationRecord)
    Object.const_set(:MinimalOperationRecord, Class.new(ActiveRecord::Base)) unless defined?(MinimalOperationRecord)
    Object.const_set(:TestModel, Class.new(ActiveRecord::Base)) unless defined?(TestModel)
  end
end
