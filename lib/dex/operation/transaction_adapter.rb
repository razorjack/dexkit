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
        elsif defined?(Mongoid)
          MongoidAdapter
        end
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

          callbacks = Thread.current[AFTER_COMMIT_KEY]
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

          Thread.current[AFTER_COMMIT_KEY] = []
          block_completed = false
          result = Mongoid.transaction do
            value = block.call
            block_completed = true
            value
          end

          if block_completed
            Thread.current[AFTER_COMMIT_KEY].each(&:call)
          end

          result
        ensure
          Thread.current[AFTER_COMMIT_KEY] = nil if outermost
        end

        # NOTE: Only detects transactions opened via MongoidAdapter.wrap (i.e. Dex operations).
        # Ambient Mongoid.transaction blocks opened outside Dex are invisible here —
        # the callback will fire immediately instead of deferring to the outer commit.
        def self.after_commit(&block)
          callbacks = Thread.current[AFTER_COMMIT_KEY]
          if callbacks
            callbacks << block
          else
            block.call
          end
        end

        def self.rollback_exception_class
          Mongoid::Errors::Rollback
        end
      end
    end
  end
end
