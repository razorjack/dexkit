# frozen_string_literal: true

module Dex
  class OperationFailed < StandardError
    attr_reader :operation_name, :exception_class, :exception_message

    def initialize(operation_name:, exception_class:, exception_message:)
      @operation_name = operation_name
      @exception_class = exception_class
      @exception_message = exception_message
      super("#{operation_name} failed with #{exception_class}: #{exception_message}")
    end
  end
end
