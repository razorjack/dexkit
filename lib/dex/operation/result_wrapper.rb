# frozen_string_literal: true

module Dex
  module ResultWrapper
    module ClassMethods
      def success(type)
        @_success_type = type
      end

      def error(*codes)
        invalid = codes.reject { |c| c.is_a?(Symbol) }
        if invalid.any?
          raise ArgumentError, "error codes must be Symbols, got: #{invalid.map(&:inspect).join(", ")}"
        end

        @_declared_errors ||= []
        @_declared_errors.concat(codes)
      end

      def _success_type
        @_success_type || (superclass.respond_to?(:_success_type) ? superclass._success_type : nil)
      end

      def _declared_errors
        parent = superclass.respond_to?(:_declared_errors) ? superclass._declared_errors : []
        own = @_declared_errors || []
        (parent + own).uniq
      end

      def _has_declared_errors?
        _declared_errors.any?
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def _result_wrap
      halted = catch(:_dex_halt) { yield }
      if halted.is_a?(Operation::Halt)
        if halted.success?
          _result_validate_success_type!(halted.value)
          halted.value
        else
          raise Dex::Error.new(halted.error_code, halted.error_message, details: halted.error_details)
        end
      else
        _result_validate_success_type!(halted)
        halted
      end
    end

    def error!(code, message = nil, details: nil)
      if self.class._has_declared_errors? && !self.class._declared_errors.include?(code)
        raise ArgumentError, "Undeclared error code: #{code.inspect}. Declared: #{self.class._declared_errors.inspect}"
      end

      throw(:_dex_halt, Operation::Halt.new(type: :error, error_code: code, error_message: message,
        error_details: details))
    end

    def success!(value = nil, **attrs)
      throw(:_dex_halt, Operation::Halt.new(type: :success, value: attrs.empty? ? value : attrs))
    end

    def assert!(*args, &block)
      if block
        code = args[0]
        value = yield
      else
        value, code = args
      end

      error!(code) unless value
      value
    end

    private

    def _result_validate_success_type!(value)
      return if value.nil?

      success_type = self.class._success_type
      return unless success_type
      return if success_type === value

      raise ArgumentError,
        "#{self.class.name || "Operation"} declared `success #{success_type.inspect}` but returned #{value.class}"
    end
  end
end
