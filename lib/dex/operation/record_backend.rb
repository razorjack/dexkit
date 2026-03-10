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

        def find_by_once_key(key)
          raise NotImplementedError
        end

        def find_expired_once_key(key)
          raise NotImplementedError
        end

        def find_pending_once_key(key)
          raise NotImplementedError
        end

        def update_record_by_once_key(key, **attributes)
          raise NotImplementedError
        end

        def unique_constraint_error?(exception)
          raise NotImplementedError
        end

        def safe_attributes(attributes)
          attributes.select { |key, _| has_field?(key.to_s) }
        end

        def missing_fields(*fields)
          fields.flatten.uniq.reject { |field_name| has_field?(field_name) }
        end

        def ensure_fields!(*fields, feature:)
          missing = missing_fields(*fields)
          return if missing.empty?

          raise ArgumentError,
            "Dex record_class #{record_class} is missing required attributes for #{feature}: #{missing.join(", ")}. " \
            "Define these attributes on #{record_class} or disable #{feature}."
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

        def find_by_once_key(key)
          scope = record_class.where(once_key: key, status: %w[completed error])
          scope = scope.where("once_key_expires_at IS NULL OR once_key_expires_at >= ?", Time.now) if has_field?("once_key_expires_at")
          scope.first
        end

        def find_expired_once_key(key)
          return nil unless has_field?("once_key_expires_at")

          record_class
            .where(once_key: key, status: %w[completed error])
            .where("once_key_expires_at IS NOT NULL AND once_key_expires_at < ?", Time.now)
            .first
        end

        def find_pending_once_key(key)
          record_class.where(once_key: key, status: %w[pending running]).first
        end

        def update_record_by_once_key(key, **attributes)
          record = record_class.where(once_key: key, status: %w[completed error]).first
          record&.update!(safe_attributes(attributes))
        end

        def unique_constraint_error?(exception)
          defined?(ActiveRecord::RecordNotUnique) && exception.is_a?(ActiveRecord::RecordNotUnique)
        end

        def has_field?(field_name)
          @column_set.include?(field_name.to_s)
        end
      end

      class MongoidAdapter < Base
        def find_by_once_key(key)
          now = Time.now
          record_class.where(
            :once_key => key,
            :status.in => %w[completed error]
          ).and(
            record_class.or(
              { once_key_expires_at: nil },
              { :once_key_expires_at.gte => now }
            )
          ).first
        end

        def find_expired_once_key(key)
          return nil unless has_field?("once_key_expires_at")

          record_class.where(
            :once_key => key,
            :status.in => %w[completed error],
            :once_key_expires_at.ne => nil,
            :once_key_expires_at.lt => Time.now
          ).first
        end

        def find_pending_once_key(key)
          record_class.where(:once_key => key, :status.in => %w[pending running]).first
        end

        def update_record_by_once_key(key, **attributes)
          record = record_class.where(:once_key => key, :status.in => %w[completed error]).first
          record&.update!(safe_attributes(attributes))
        end

        def unique_constraint_error?(exception)
          defined?(Mongo::Error::OperationFailure) &&
            exception.is_a?(Mongo::Error::OperationFailure) &&
            exception.code == 11_000
        end

        def has_field?(field_name)
          record_class.fields.key?(field_name.to_s)
        end
      end
    end
  end
end
