# frozen_string_literal: true

module Dex
  class Operation
    module TransactionAdapter
      def self.for(adapter_name)
        case adapter_name&.to_sym
        when :active_record
          ActiveRecordAdapter
        when :mongoid
          MongoidAdapter
        when nil
          detect
        else
          raise ArgumentError, "Unknown transaction adapter: #{adapter_name}"
        end
      end

      def self.detect
        if defined?(ActiveRecord::Base)
          ActiveRecordAdapter
        end
      end

      def self.ambient_mongoid_transaction?
        return false unless defined?(Mongoid::Threaded) && Mongoid::Threaded.respond_to?(:sessions)

        Mongoid::Threaded.sessions.values.any? do |session|
          session.respond_to?(:in_transaction?) && session.in_transaction?
        end
      rescue
        false
      end

      module ActiveRecordAdapter
        def self.wrap(&block)
          unless defined?(ActiveRecord::Base)
            raise LoadError, "ActiveRecord is required for transactions"
          end
          ActiveRecord::Base.transaction(&block)
        end

        def self.after_commit(&block)
          unless defined?(ActiveRecord) && ActiveRecord.respond_to?(:after_all_transactions_commit)
            raise LoadError, "after_commit requires Rails 7.2+"
          end

          ActiveRecord.after_all_transactions_commit(&block)
        end

        def self.rollback_exception_class
          ActiveRecord::Rollback
        end
      end

      module MongoidAdapter
        AFTER_COMMIT_KEY = :_dex_mongoid_after_commit

        def self.wrap(&block)
          unless defined?(Mongoid)
            raise LoadError, "Mongoid is required for transactions"
          end

          callbacks = Fiber[AFTER_COMMIT_KEY]
          outermost = callbacks.nil?

          unless outermost
            snapshot = callbacks.length
            begin
              return block.call
            rescue rollback_exception_class
              callbacks.slice!(snapshot..)
              return nil
            rescue StandardError # rubocop:disable Style/RescueStandardError
              callbacks.slice!(snapshot..)
              raise
            end
          end

          Fiber[AFTER_COMMIT_KEY] = []
          block_completed = false
          result = Mongoid.transaction do
            value = block.call
            block_completed = true
            value
          end

          if block_completed
            Fiber[AFTER_COMMIT_KEY].each(&:call)
          end

          result
        rescue => e
          raise _transactions_not_supported_message if _transactions_not_supported?(e)

          raise
        ensure
          Fiber[AFTER_COMMIT_KEY] = nil if outermost
        end

        # Mongoid stores sessions on the current thread rather than the current fiber.
        # A sibling fiber on the same thread therefore participates in the same
        # ambient transaction, so we must consult Mongoid's thread-scoped session
        # state here instead of relying on Dex's fiber-local queue alone.
        def self.after_commit(&block)
          callbacks = Fiber[AFTER_COMMIT_KEY]
          if callbacks
            callbacks << block
          elsif TransactionAdapter.ambient_mongoid_transaction?
            raise(
              "after_commit cannot attach to an ambient Mongoid.transaction opened outside Dex. " \
              "Use Dex-managed transactions or an `after` callback instead."
            )
          else
            block.call
          end
        end

        def self.rollback_exception_class
          Mongoid::Errors::Rollback
        end

        def self._transactions_not_supported?(exception)
          defined?(Mongoid::Errors::TransactionsNotSupported) &&
            exception.is_a?(Mongoid::Errors::TransactionsNotSupported)
        end

        def self._transactions_not_supported_message
          "Mongoid transactions require a MongoDB replica set or sharded cluster. " \
            "Configure Dex.transaction_adapter = :mongoid only when transactions are supported, " \
            "or disable transactions for this operation."
        end
      end
    end
  end
end
