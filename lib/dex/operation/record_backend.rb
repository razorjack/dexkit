# frozen_string_literal: true

module Dex
  class Operation
    module RecordBackend
      def self.for(record_class)
        return nil unless record_class

        if defined?(ActiveRecord::Base) && record_class < ActiveRecord::Base
          ActiveRecordAdapter.new(record_class)
        elsif defined?(Mongoid::Document) && record_class.include?(Mongoid::Document)
          MongoidAdapter.new(record_class)
        else
          raise ArgumentError, "record_class must inherit from ActiveRecord::Base or include Mongoid::Document"
        end
      end

      class Base
        attr_reader :record_class

        def initialize(record_class)
          @record_class = record_class
        end

        def create_record(attributes)
          record_class.create!(safe_attributes(attributes))
        end

        def find_record(id)
          record_class.find(id)
        end

        def update_record(id, attributes)
          record_class.find(id).update!(safe_attributes(attributes))
        end

        def safe_attributes(attributes)
          attributes.select { |key, _| has_field?(key.to_s) }
        end

        def has_field?(field_name)
          raise NotImplementedError
        end
      end

      class ActiveRecordAdapter < Base
        def initialize(record_class)
          super
          @column_set = record_class.column_names.to_set
        end

        def has_field?(field_name)
          @column_set.include?(field_name.to_s)
        end
      end

      class MongoidAdapter < Base
        def has_field?(field_name)
          record_class.fields.key?(field_name.to_s)
        end
      end
    end
  end
end
