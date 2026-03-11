# frozen_string_literal: true

module Dex
  class Operation
    module TransactionAdapter
      KNOWN_ADAPTERS = %i[active_record].freeze

      def self.for(adapter_name)
        case normalize_name(adapter_name)
        when :active_record
          ActiveRecordAdapter
        when nil
          detect
        end
      end

      def self.known_adapters
        KNOWN_ADAPTERS
      end

      def self.normalize_name(adapter_name)
        return nil if adapter_name.nil?

        normalized = adapter_name.to_sym
        return normalized if KNOWN_ADAPTERS.include?(normalized)

        raise ArgumentError,
          "unknown transaction adapter: #{adapter_name.inspect}. " \
          "Known: #{KNOWN_ADAPTERS.map(&:inspect).join(", ")}"
      end

      def self.detect
        return unless defined?(ActiveRecord::Base)
        return unless active_record_pool?

        ActiveRecordAdapter
      end

      def self.active_record_pool?
        !ActiveRecord::Base.connection_handler.retrieve_connection_pool(
          ActiveRecord::Base.connection_specification_name,
          strict: false
        ).nil?
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
    end
  end
end
