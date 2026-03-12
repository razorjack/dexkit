# frozen_string_literal: true

# Wrapper modules (loaded before class body so `include`/`use` can find them)
require_relative "operation/result_wrapper"
require_relative "operation/once_wrapper"
require_relative "operation/record_wrapper"
require_relative "operation/trace_wrapper"
require_relative "operation/transaction_wrapper"
require_relative "operation/lock_wrapper"
require_relative "operation/async_wrapper"
require_relative "operation/safe_wrapper"
require_relative "operation/rescue_wrapper"
require_relative "operation/callback_wrapper"
require_relative "operation/guard_wrapper"

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

    RESERVED_PROP_NAMES = %i[call perform async safe once initialize].to_set.freeze

    include Executable
    include PropsSetup
    include TypeCoercion
    include ContextSetup

    Contract = Data.define(:params, :success, :errors, :guards) do
      attr_reader :source_class

      def initialize(params:, success:, errors:, guards:, source_class: nil)
        @source_class = source_class
        super(params: params, success: success, errors: errors, guards: guards)
      end

      def to_h
        if @source_class
          Operation::Export.build_hash(@source_class, self)
        else
          super
        end
      end

      def to_json_schema(**options)
        unless @source_class
          raise ArgumentError, "to_json_schema requires a source_class (use OperationClass.contract.to_json_schema)"
        end

        Operation::Export.build_json_schema(@source_class, self, **options)
      end
    end

    extend Registry

    class << self
      def contract
        Contract.new(
          params: _contract_params,
          success: _success_type,
          errors: _declared_errors,
          guards: _contract_guards,
          source_class: self
        )
      end

      def export(format: :hash, **options)
        unless %i[hash json_schema].include?(format)
          raise ArgumentError, "unknown format: #{format.inspect}. Known: :hash, :json_schema"
        end

        sorted = registry.sort_by(&:name)
        sorted.map do |klass|
          case format
          when :hash then klass.contract.to_h
          when :json_schema then klass.contract.to_json_schema(**options)
          end
        end
      end

      private

      def _contract_params
        return {} unless respond_to?(:literal_properties)

        literal_properties.each_with_object({}) do |prop, hash|
          hash[prop.name] = prop.type
        end
      end

      def _contract_guards
        return [] unless respond_to?(:_guard_list)

        _guard_list.map do |g|
          { name: g.name, message: g.message, requires: g.requires }
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

    use TraceWrapper, at: :outer
    use ResultWrapper
    use GuardWrapper
    use OnceWrapper
    use LockWrapper
    use RecordWrapper
    use TransactionWrapper
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
require_relative "operation/explain"
require_relative "operation/export"

Dex::Operation.extend(Dex::Operation::Explain)

# Top-level aliases (depend on Operation::Ok/Err)
require_relative "match"

# Make Ok/Err available without prefix inside operations
Dex::Operation.include(Dex::Match)
