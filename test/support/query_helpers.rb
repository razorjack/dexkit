# frozen_string_literal: true

module QueryHelpers
  QUERY_USER_FIXTURES = [
    { name: "Alice", email: "alice@example.com", role: "admin", age: 30, status: "active" },
    { name: "Bob", email: "bob@example.com", role: "user", age: 25, status: "active" },
    { name: "Charlie", email: "charlie@example.com", role: "user", age: 35, status: "inactive" }
  ].freeze

  include TemporaryConstants

  def teardown
    _cleanup_tracked_constants(:query)
    super
  end

  def define_query(name, parent: Dex::Query, scope_model: nil, &block)
    _track_constant(:query, name, _build_query_class(parent: parent, scope_model: scope_model, &block))
  end

  def build_query(parent: Dex::Query, scope_model: nil, &block)
    _build_query_class(parent: parent, scope_model: scope_model, &block)
  end

  def seed_query_users(*records)
    records = QUERY_USER_FIXTURES if records.empty?
    records.each { |attrs| QueryUser.create!(attrs) }
  end

  def setup_query_database
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :query_users, force: true do |t|
          t.string :name
          t.string :email
          t.string :role
          t.integer :age
          t.string :status
          t.timestamps
        end
      end
    end

    Object.const_set(:QueryUser, Class.new(ActiveRecord::Base)) unless defined?(QueryUser)
  end

  private

  def _build_query_class(parent:, scope_model:, &block)
    query_class = Class.new(parent)
    if scope_model
      query_class.class_eval do
        scope { scope_model.all }
      end
    end
    query_class.class_eval(&block) if block
    query_class
  end
end
