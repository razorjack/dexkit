# frozen_string_literal: true

module Dex
  module TransactionWrapper
    extend Dex::Concern

    DEFERRED_CALLBACKS_KEY = :_dex_after_commit_queue

    def _transaction_wrap
      deferred = Fiber[DEFERRED_CALLBACKS_KEY]
      outermost = deferred.nil?
      Fiber[DEFERRED_CALLBACKS_KEY] = [] if outermost
      snapshot = Fiber[DEFERRED_CALLBACKS_KEY].length

      result, interceptor = if _transaction_enabled?
        _transaction_run_adapter(snapshot) { yield }
      else
        _transaction_run_deferred(snapshot) { yield }
      end

      _transaction_flush_deferred if outermost

      interceptor&.rethrow!
      result
    rescue # rubocop:disable Style/RescueStandardError -- explicit for clarity
      Fiber[DEFERRED_CALLBACKS_KEY]&.slice!(snapshot..)
      raise
    ensure
      Fiber[DEFERRED_CALLBACKS_KEY] = nil if outermost
    end

    def after_commit(&block)
      raise ArgumentError, "after_commit requires a block" unless block

      deferred = Fiber[DEFERRED_CALLBACKS_KEY]
      if deferred
        deferred << block
      else
        block.call
      end
    end

    TRANSACTION_KNOWN_ADAPTERS = %i[active_record].freeze

    module ClassMethods
      def transaction(enabled_or_options = nil, **options)
        validate_options!(options, %i[adapter], :transaction)

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

    def _transaction_run_adapter(snapshot)
      interceptor = nil
      result = _transaction_execute do
        interceptor = Operation::HaltInterceptor.new { yield }
        raise _transaction_adapter.rollback_exception_class if interceptor.error?
        interceptor.result
      end

      if interceptor&.error?
        Fiber[DEFERRED_CALLBACKS_KEY]&.slice!(snapshot..)
        interceptor.rethrow!
      end

      [result, interceptor]
    end

    def _transaction_run_deferred(snapshot)
      interceptor = Operation::HaltInterceptor.new { yield }

      if interceptor.error?
        Fiber[DEFERRED_CALLBACKS_KEY]&.slice!(snapshot..)
        interceptor.rethrow!
      end

      [interceptor.result, interceptor]
    end

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

    def _transaction_flush_deferred
      callbacks = Fiber[DEFERRED_CALLBACKS_KEY]
      return if callbacks.empty?

      flush = -> { callbacks.each(&:call) }
      enabled = self.class.settings_for(:transaction).fetch(:enabled, true)
      adapter = enabled && _transaction_adapter
      if adapter
        adapter.after_commit(&flush)
      else
        flush.call
      end
    end

    def _transaction_execute(&block)
      _transaction_adapter.wrap(&block)
    end
  end
end
