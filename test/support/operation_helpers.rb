# frozen_string_literal: true

module OperationHelpers
  def self.included(base)
    base.class_eval do
      def teardown
        _cleanup_operation_constants
        super
      end
    end
  end

  # Defines a named operation class and tracks it for automatic cleanup
  # @param name [Symbol] The constant name (e.g., :TestOp)
  # @param parent [Class] Optional parent class (defaults to Dex::Operation)
  # @param block [Proc] Block to define the operation class
  # @return [Class] The created operation class
  def define_operation(name, parent: Dex::Operation, &block)
    op_class = Class.new(parent, &block)
    Object.const_set(name, op_class)
    _tracked_operation_constants << name
    op_class
  end

  # Builds an anonymous operation class (no constant tracking needed)
  # @param parent [Class] Optional parent class (defaults to Dex::Operation)
  # @param block [Proc] Block to define the operation class
  # @return [Class] The created operation class
  def build_operation(parent: Dex::Operation, &block)
    Class.new(parent, &block)
  end

  # Builds an operation class with optional params schema, success type, error codes, and perform body
  # @param name [Symbol, nil] Optional constant name for operations requiring a class name
  # @param parent [Class] Optional parent class (defaults to Dex::Operation)
  # @param params [Hash, Proc, nil] Params schema definition
  # @param success [Dry::Types::Type, nil] Success type declaration
  # @param errors [Array<Symbol>, nil] Declared error codes
  # @param block [Proc] Perform implementation
  # @return [Class] The created operation class
  def operation(name: nil, parent: Dex::Operation, params: nil, success: nil, errors: nil, &block)
    op_class = if name
      define_operation(name, parent: parent)
    else
      build_operation(parent: parent)
    end

    _define_schema(op_class, :params, params)
    op_class.success(success) if success
    op_class.error(*errors) if errors

    op_class.class_eval do
      define_method(:perform, &block) if block
    end

    op_class
  end

  # Configures Dex.record_class for the duration of the block
  # @param record_class [Class] The ActiveRecord class to use for recording
  # @param block [Proc] Block to execute with recording enabled
  def with_recording(record_class: OperationRecord, &block)
    Dex.configure { |c| c.record_class = record_class }
    Dex.reset_record_backend!
    block.call
  ensure
    Dex.configure { |c| c.record_class = nil }
    Dex.reset_record_backend!
  end

  private

  def _tracked_operation_constants
    @_tracked_operation_constants ||= []
  end

  def _cleanup_operation_constants
    return unless defined?(@_tracked_operation_constants)

    @_tracked_operation_constants.each do |const_name|
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
    end
    @_tracked_operation_constants.clear
  end

  def _define_schema(op_class, schema_type, definition)
    return if definition.nil?

    case definition
    when Hash
      op_class.public_send(schema_type) do
        definition.each do |name, type|
          attribute name, type
        end
      end
    when Proc
      op_class.public_send(schema_type, &definition)
    else
      raise ArgumentError, "#{schema_type} must be a Hash or Proc"
    end
  end
end
