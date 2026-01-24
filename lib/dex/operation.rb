module Dex
  module RecordWrapper
    def perform(*, **)
      _record_save! if _record_enabled?
      super
    end

    private

    def _record_enabled?
      return false unless Dex.record_backend
      return false unless self.class.name # Anonymous classes can't be recorded

      record_settings = self.class.settings_for(:record)
      record_settings.fetch(:enabled, true)
    end

    def _record_save!
      Dex.record_backend.create_record(_record_attributes)
    rescue => e
      _record_handle_error(e)
    end

    def _record_attributes
      {
        name: self.class.name,
        params: _record_params,
        performed_at: Time.now
      }
    end

    def _record_params
      return {} unless respond_to?(:params) && params
      params.as_json
    end

    def _record_handle_error(error)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn "[Dex] Failed to record operation: #{error.message}"
      end
    end

    module ClassMethods
      def record(enabled = nil, **options)
        if enabled == false
          set :record, enabled: false
        elsif enabled == true || enabled.nil?
          set :record, enabled: true, **options
        end
      end
    end

    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end
  end

  module ParamsWrapper
    @_params_schema = Dex::Parameters

    def initialize(*args, **kwargs)
      if !kwargs.empty?
        @params = self.class._params_schema.new(kwargs)
      end
      super
    end

    module ClassMethods
      def params(&block)
        klass = Class.new(Dex::Parameters, &block)
        const_set(:Params, klass)
        @_params_schema = klass
      end

      def _params_schema
        @_params_schema
      end
    end

    def self.prepended(base)
      base.attr_reader :params

      class << base
        prepend ClassMethods
      end
    end
  end

  module Settings
    module ClassMethods
      def set(key, **options)
        @_settings ||= {}
        @_settings[key] = (@_settings[key] || {}).merge(options)
      end

      def settings_for(key)
        parent_settings = if superclass.respond_to?(:settings_for)
          superclass.settings_for(key) || {}
        else
          {}
        end
        own_settings = @_settings&.dig(key) || {}
        parent_settings.merge(own_settings)
      end
    end

    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end
  end

  module AsyncWrapper
    module ClassMethods
      def async(**options)
        set(:async, **options)
      end
    end

    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end

    def async(**options)
      Operation::AsyncProxy.new(self, **options)
    end
  end

  class Operation
    def initialize(*, **); end
    def perform(*, **); end

    def self.inherited(base)
      base.prepend RecordWrapper
      base.prepend ParamsWrapper
      base.prepend Settings
      base.prepend AsyncWrapper
    end

    class AsyncProxy
      def initialize(operation, **runtime_options)
        @operation = operation
        @runtime_options = runtime_options
      end

      def perform
        ensure_active_job_loaded!
        job = Operation::Job
        job = job.set(queue: queue) if queue
        job = job.set(wait_until: scheduled_at) if scheduled_at
        job = job.set(wait: scheduled_in) if scheduled_in
        job.perform_later(class_name: operation_class_name, params: serialized_params)
      end

      private

      def ensure_active_job_loaded!
        return if defined?(ActiveJob::Base)
        raise LoadError, "ActiveJob is required for async operations. Add 'activejob' to your Gemfile."
      end

      def merged_options
        @operation.class.settings_for(:async).merge(@runtime_options)
      end

      def queue = merged_options[:queue]
      def scheduled_at = merged_options[:at]
      def scheduled_in = merged_options[:in]
      def operation_class_name = @operation.class.name
      def serialized_params = @operation.params.to_h
    end

    # Job class is defined lazily when ActiveJob is loaded
    def self.const_missing(name)
      if name == :Job && defined?(ActiveJob::Base)
        const_set(:Job, Class.new(ActiveJob::Base) do
          def perform(class_name:, params:)
            klass = class_name.constantize
            klass.new(**params.deep_symbolize_keys).perform
          end
        end)
      else
        super
      end
    end

    module RecordBackend
      def self.for(record_class)
        return nil unless record_class

        if defined?(ActiveRecord::Base) && record_class < ActiveRecord::Base
          ActiveRecordAdapter.new(record_class)
        elsif defined?(Mongoid::Document) && record_class.included_modules.include?(Mongoid::Document)
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

        def safe_attributes(attributes)
          attributes.select { |key, _| has_field?(key.to_s) }
        end

        def has_field?(field_name)
          raise NotImplementedError
        end
      end

      class ActiveRecordAdapter < Base
        def has_field?(field_name)
          record_class.column_names.include?(field_name.to_s)
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
