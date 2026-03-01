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

        def self.rollback_exception_class
          ActiveRecord::Rollback
        end
      end

      module MongoidAdapter
        def self.wrap(&block)
          unless defined?(Mongoid)
            raise LoadError, "Mongoid is required for transactions"
          end
          Mongoid.transaction(&block)
        end

        def self.rollback_exception_class
          Mongoid::Errors::Rollback
        end
      end
    end
  end
end
