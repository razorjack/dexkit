# frozen_string_literal: true

module Dex
  module TransactionWrapper
    def self.included(base)
      base.extend(ClassMethods)
    end

    def _transaction_wrap
      return yield unless _transaction_enabled?

      halted = nil
      result = _transaction_execute do
        halted_value = catch(:_dex_halt) { yield }
        if halted_value.is_a?(Operation::Halt)
          halted = halted_value
          raise _transaction_adapter.rollback_exception_class if halted.error?
          halted.value
        else
          halted_value
        end
      end

      throw(:_dex_halt, halted) if halted
      result
    end

    TRANSACTION_KNOWN_ADAPTERS = %i[active_record mongoid].freeze
    TRANSACTION_KNOWN_OPTIONS = %i[adapter].freeze

    module ClassMethods
      def transaction(enabled_or_options = nil, **options)
        unknown = options.keys - TransactionWrapper::TRANSACTION_KNOWN_OPTIONS
        if unknown.any?
          raise ArgumentError,
            "unknown transaction option(s): #{unknown.map(&:inspect).join(", ")}. " \
            "Known: #{TransactionWrapper::TRANSACTION_KNOWN_OPTIONS.map(&:inspect).join(", ")}"
        end

        case enabled_or_options
        when false
          set :transaction, enabled: false
        when true, nil
          _transaction_validate_adapter!(options[:adapter]) if options.key?(:adapter)
          set :transaction, enabled: true, **options
        when Symbol
          _transaction_validate_adapter!(enabled_or_options)
          set :transaction, enabled: true, adapter: enabled_or_options, **options
        else
          raise ArgumentError,
            "transaction expects true, false, nil, or a Symbol adapter, got: #{enabled_or_options.inspect}"
        end
      end

      private

      def _transaction_validate_adapter!(adapter)
        return if adapter.nil?

        unless TransactionWrapper::TRANSACTION_KNOWN_ADAPTERS.include?(adapter.to_sym)
          raise ArgumentError,
            "unknown transaction adapter: #{adapter.inspect}. " \
            "Known: #{TransactionWrapper::TRANSACTION_KNOWN_ADAPTERS.map(&:inspect).join(", ")}"
        end
      end
    end

    private

    def _transaction_enabled?
      settings = self.class.settings_for(:transaction)
      return false unless settings.fetch(:enabled, true)

      !_transaction_adapter.nil?
    end

    def _transaction_adapter
      settings = self.class.settings_for(:transaction)
      adapter_name = settings.fetch(:adapter, Dex.transaction_adapter)
      Operation::TransactionAdapter.for(adapter_name)
    end

    def _transaction_execute(&block)
      _transaction_adapter.wrap(&block)
    end
  end
end
