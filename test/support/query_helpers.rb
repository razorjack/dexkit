# frozen_string_literal: true

module QueryHelpers
  def teardown
    _cleanup_query_constants
    super
  end

  def define_query(name, parent: Dex::Query, &block)
    query_class = Class.new(parent, &block)
    Object.const_set(name, query_class)
    _tracked_query_constants << name
    query_class
  end

  def build_query(parent: Dex::Query, &block)
    Class.new(parent, &block)
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

  def _tracked_query_constants
    @_tracked_query_constants ||= []
  end

  def _cleanup_query_constants
    return unless defined?(@_tracked_query_constants)

    @_tracked_query_constants.each do |const_name|
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
    end
    @_tracked_query_constants.clear
  end
end
