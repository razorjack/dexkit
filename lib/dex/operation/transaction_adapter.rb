# frozen_string_literal: true

module Dex
  class Operation
    module TransactionAdapter
      def self.for(adapter_name)
        case adapter_name&.to_sym
        when :active_record
          ActiveRecordAdapter
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
