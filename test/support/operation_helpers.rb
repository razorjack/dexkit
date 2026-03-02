# frozen_string_literal: true

module OperationHelpers
  def teardown
    _cleanup_operation_constants
    super
  end

  # Defines a named operation class and tracks it for automatic cleanup
  def define_operation(name, parent: Dex::Operation, &block)
    op_class = Class.new(parent, &block)
    Object.const_set(name, op_class)
    _tracked_operation_constants << name
    op_class
  end

  # Builds an anonymous operation class (no constant tracking needed)
  def build_operation(parent: Dex::Operation, &block)
    Class.new(parent, &block)
  end

  # Builds an operation class with optional props, success type, error codes, and perform body
  def operation(name: nil, parent: Dex::Operation, params: nil, success: nil, errors: nil, &block)
    op_class = if name
      define_operation(name, parent: parent)
    else
      build_operation(parent: parent)
    end

    _define_props(op_class, params)
    op_class.success(success) if success
    op_class.error(*errors) if errors

    op_class.class_eval do
      define_method(:perform, &block) if block
    end

    op_class
  end

  # Configures Dex.record_class for the duration of the block
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

  def _define_props(op_class, definition)
    return if definition.nil?

    case definition
    when Hash
      definition.each do |name, type|
        op_class.prop(name, type)
      end
    when Proc
      op_class.class_eval(&definition)
    else
      raise ArgumentError, "params must be a Hash or Proc"
    end
  end
end
