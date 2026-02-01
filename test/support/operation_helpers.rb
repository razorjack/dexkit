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
end
