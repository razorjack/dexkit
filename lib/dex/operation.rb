# frozen_string_literal: true

# Wrapper modules (loaded before class body so `include`/`use` can find them)
require_relative "operation/result_wrapper"
require_relative "operation/record_wrapper"
require_relative "operation/transaction_wrapper"
require_relative "operation/lock_wrapper"
require_relative "operation/async_wrapper"
require_relative "operation/safe_wrapper"
require_relative "operation/rescue_wrapper"
require_relative "operation/callback_wrapper"

module Dex
  class Operation
    Halt = Struct.new(:type, :value, :error_code, :error_message, :error_details, keyword_init: true) do
      def success? = type == :success
      def error? = type == :error
    end

    class HaltInterceptor
      attr_reader :result, :halt

      def initialize
        raw = catch(:_dex_halt) { yield }
        if raw.is_a?(Halt)
          @halt = raw
          @result = raw.success? ? raw.value : nil
        else
          @halt = nil
          @result = raw
        end
      end

      def halted? = !@halt.nil?
      def success? = !error?
      def error? = @halt&.error? || false

      def rethrow!
        throw(:_dex_halt, @halt) if halted?
      end
    end

    RESERVED_PROP_NAMES = %i[call perform async safe initialize].to_set.freeze

    include Executable
    include PropsSetup
    include TypeCoercion

    Contract = Data.define(:params, :success, :errors)

    class << self
      def contract
        Contract.new(
          params: _contract_params,
          success: _success_type,
          errors: _declared_errors
        )
      end

      private

      def _contract_params
        return {} unless respond_to?(:literal_properties)

        literal_properties.each_with_object({}) do |prop, hash|
          hash[prop.name] = prop.type
        end
      end
    end

    def perform(*, **)
    end

    def self.method_added(method_name)
      super
      return unless method_name == :perform

      private :perform
    end

    private :perform

    def self.call(**kwargs)
      new(**kwargs).call
    end

    include AsyncWrapper
    include SafeWrapper

    use ResultWrapper
    use LockWrapper
    use TransactionWrapper
    use RecordWrapper
    use RescueWrapper
    use CallbackWrapper
  end
end

# Nested classes (reopen Operation after it's defined)
require_relative "operation/outcome"
require_relative "operation/async_proxy"
require_relative "operation/record_backend"
require_relative "operation/transaction_adapter"
require_relative "operation/jobs"

# Top-level aliases (depend on Operation::Ok/Err)
require_relative "match"

# Make Ok/Err available without prefix inside operations
Dex::Operation.include(Dex::Match)
