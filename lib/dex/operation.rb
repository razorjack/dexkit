module Dex
  module RecordWrapper
    def perform(*, **)
      # Operation::Record.create!(
      #   name: self.class.name,
      #   params: self.params.as_json
      # )
      super
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

    class Job < ActiveJob::Base
      def perform(class_name:, params:)
        klass = class_name.constantize
        klass.new(**params.deep_symbolize_keys).perform
      end
    end
  end
end
