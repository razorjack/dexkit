# frozen_string_literal: true

module Dex
  class Operation
    class Ok
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def ok? = true
      def error? = false

      def value! = @value

      def method_missing(method, *args, &block)
        if @value.respond_to?(method)
          @value.public_send(method, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        @value.respond_to?(method, include_private) || super
      end

      def deconstruct_keys(keys)
        return { value: @value } unless @value.respond_to?(:deconstruct_keys)
        @value.deconstruct_keys(keys)
      end
    end

    class Err
      attr_reader :error

      def initialize(error)
        @error = error
      end

      def ok? = false
      def error? = true

      def value = nil
      def value! = raise @error

      def code = @error.code
      def message = @error.message
      def details = @error.details

      def deconstruct_keys(keys)
        { code: @error.code, message: @error.message, details: @error.details }
      end
    end

    class SafeProxy
      def initialize(operation)
        @operation = operation
      end

      def call
        result = @operation.call
        Operation::Ok.new(result)
      rescue Dex::Error => e
        Operation::Err.new(e)
      end
    end
  end
end
