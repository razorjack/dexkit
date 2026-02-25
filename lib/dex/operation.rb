module Dex
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message = nil, details: nil)
      @code = code
      @details = details
      super(message || code.to_s)
    end

    def deconstruct_keys(keys)
      { code: @code, message: message, details: @details }
    end
  end

  module RecordWrapper
    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end

    def perform(*, **)
      result = super
      _record_save!(result) if _record_enabled?
      result
    end

    module ClassMethods
      def record(enabled = nil, **options)
        if enabled == false
          set :record, enabled: false
        elsif enabled == true || enabled.nil?
          # Default: record both params and response
          merged = { enabled: true, params: true, response: true }.merge(options)
          set :record, **merged
        end
      end
    end

    private

    def _record_enabled?
      return false unless Dex.record_backend
      return false unless self.class.name # Anonymous classes can't be recorded

      record_settings = self.class.settings_for(:record)
      record_settings.fetch(:enabled, true)
    end

    def _record_save!(result)
      Dex.record_backend.create_record(_record_attributes(result))
    rescue => e
      _record_handle_error(e)
    end

    def _record_attributes(result)
      attrs = { name: self.class.name, performed_at: Time.now }
      attrs[:params] = _record_params? ? _record_params : nil
      attrs[:response] = _record_response? ? _record_response(result) : nil
      attrs
    end

    def _record_params
      return {} unless respond_to?(:params) && params
      params.as_json
    end

    def _record_params?
      self.class.settings_for(:record).fetch(:params, true)
    end

    def _record_response?
      self.class.settings_for(:record).fetch(:response, true)
    end

    def _record_response(result)
      case result
      when nil then nil
      when Dex::Parameters then result.as_json
      when Hash
        # If there's a result schema, wrap the hash to get proper serialization
        if self.class._result_has_schema?
          self.class._result_schema.new(result).as_json
        else
          result
        end
      else { value: result }
      end
    end

    def _record_handle_error(error)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn "[Dex] Failed to record operation: #{error.message}"
      end
    end
  end

  module TransactionWrapper
    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end

    def perform(*, **)
      if _transaction_enabled?
        _transaction_execute { super }
      else
        super
      end
    end

    module ClassMethods
      def transaction(enabled_or_options = nil, **options)
        case enabled_or_options
        when false
          set :transaction, enabled: false
        when true, nil
          set :transaction, enabled: true, **options
        when Symbol
          # Shorthand: `transaction :mongoid`
          set :transaction, enabled: true, adapter: enabled_or_options, **options
        end
      end
    end

    private

    def _transaction_enabled?
      settings = self.class.settings_for(:transaction)
      settings.fetch(:enabled, true)  # Default: enabled
    end

    def _transaction_adapter
      settings = self.class.settings_for(:transaction)
      adapter_name = settings.fetch(:adapter, Dex.transaction_adapter)
      Operation::TransactionAdapter.for(adapter_name)
    end

    def _transaction_execute(&block)
      _transaction_adapter.wrap(&block)
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

  module ResultWrapper
    module ClassMethods
      def result(&block)
        klass = Class.new(Dex::Parameters, &block)
        const_set(:Result, klass)
        @_result_schema = klass
      end

      def _result_schema
        @_result_schema
      end

      def _result_has_schema?
        !!@_result_schema
      end
    end

    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end

    def perform(*, **)
      raw_result = super
      _result_wrap(raw_result)
    end

    def error!(code, message = nil, details: nil)
      raise Dex::Error.new(code, message, details: details)
    end

    private

    def _result_wrap(raw_result)
      return raw_result unless self.class._result_has_schema?
      return raw_result unless raw_result.is_a?(Hash)

      self.class._result_schema.new(raw_result)
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

  module SafeWrapper
    def safe
      Operation::SafeProxy.new(self)
    end
  end

  module RescueWrapper
    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end

    module ClassMethods
      def rescue_from(*exception_classes, as:, message: nil)
        raise ArgumentError, "rescue_from requires at least one exception class" if exception_classes.empty?

        exception_classes.each do |klass|
          _rescue_own << { exception_class: klass, code: as, message: message }
        end
      end

      def _rescue_handlers
        parent = superclass.respond_to?(:_rescue_handlers) ? superclass._rescue_handlers : []
        parent + _rescue_own
      end

      private

      def _rescue_own
        @_rescue_handlers ||= []
      end
    end

    def perform(*, **)
      super
    rescue Dex::Error
      raise
    rescue => e
      handler = _rescue_find_handler(e)
      raise unless handler

      _rescue_convert!(e, handler)
    end

    private

    def _rescue_find_handler(exception)
      self.class._rescue_handlers.reverse_each do |handler|
        return handler if exception.is_a?(handler[:exception_class])
      end
      nil
    end

    def _rescue_convert!(exception, handler)
      msg = handler[:message] || exception.message
      raise Dex::Error.new(handler[:code], msg, details: { original: exception })
    end
  end

  module CallbackWrapper
    def self.prepended(base)
      class << base
        prepend ClassMethods
      end
    end

    module ClassMethods
      def before_perform(callable = nil, &block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:before) << entry
      end

      def after_perform(callable = nil, &block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:after) << entry
      end

      def around_perform(callable = nil, &block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:around) << entry
      end

      def _callback_list(type)
        parent_callbacks = superclass.respond_to?(:_callback_list) ? superclass._callback_list(type) : []
        parent_callbacks + _callback_own(type)
      end

      private

      def _callback_own(type)
        @_callbacks ||= { before: [], after: [], around: [] }
        @_callbacks[type]
      end
    end

    def perform(*, **)
      return super if @_callback_active
      @_callback_active = true
      _callback_run_around(self.class._callback_list(:around)) do
        _callback_run_before
        result = super
        _callback_run_after
        result
      end
    ensure
      @_callback_active = false
    end

    private

    def _callback_run_before
      self.class._callback_list(:before).each { |cb| _callback_invoke(cb) }
    end

    def _callback_run_after
      self.class._callback_list(:after).each { |cb| _callback_invoke(cb) }
    end

    def _callback_invoke(cb)
      kind, callable = cb
      case kind
      when :method then send(callable)
      when :proc then instance_exec(&callable)
      end
    end

    def _callback_run_around(chain, &core)
      if chain.empty?
        core.call
      else
        kind, callable = chain.first
        rest = chain[1..]
        continuation = -> { _callback_run_around(rest, &core) }
        case kind
        when :method then send(callable) { continuation.call }
        when :proc then instance_exec(continuation, &callable)
        end
      end
    end
  end

  class Operation
    def initialize(*, **)
    end

    def perform(*, **)
    end

    def self.inherited(base)
      base.prepend CallbackWrapper
      base.prepend RescueWrapper
      base.prepend RecordWrapper
      base.prepend TransactionWrapper
      base.prepend ResultWrapper
      base.prepend ParamsWrapper
      base.prepend Settings
      base.prepend AsyncWrapper
      base.prepend SafeWrapper
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
      def serialized_params = @operation.params&.to_h || {}
    end

    class Ok
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def ok? = true
      def error? = false

      def value! = @value

      def method_missing(method, *args, &block)
        if @value.respond_to?(method)
          @value.public_send(method, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        @value.respond_to?(method, include_private) || super
      end

      def deconstruct_keys(keys)
        return { value: @value } unless @value.respond_to?(:deconstruct_keys)
        @value.deconstruct_keys(keys)
      end
    end

    class Err
      attr_reader :error

      def initialize(error)
        @error = error
      end

      def ok? = false
      def error? = true

      def value = nil
      def value! = raise @error

      def code = @error.code
      def message = @error.message
      def details = @error.details

      def deconstruct_keys(keys)
        { code: @error.code, message: @error.message, details: @error.details }
      end
    end

    class SafeProxy
      def initialize(operation)
        @operation = operation
      end

      def perform
        result = @operation.perform
        Operation::Ok.new(result)
      rescue Dex::Error => e
        Operation::Err.new(e)
      end
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

    module TransactionAdapter
      def self.for(adapter_name)
        case adapter_name&.to_sym
        when :active_record
          ActiveRecordAdapter
        when :mongoid
          MongoidAdapter
        else
          raise ArgumentError, "Unknown transaction adapter: #{adapter_name}"
        end
      end

      module ActiveRecordAdapter
        def self.wrap(&block)
          unless defined?(ActiveRecord::Base)
            raise LoadError, "ActiveRecord is required for transactions"
          end
          ActiveRecord::Base.transaction(&block)
        end
      end

      module MongoidAdapter
        def self.wrap(&block)
          unless defined?(Mongoid)
            raise LoadError, "Mongoid is required for transactions"
          end
          Mongoid.transaction(&block)
        end
      end
    end
  end

  # Top-level aliases for clean pattern matching
  Ok = Operation::Ok
  Err = Operation::Err

  # Module for including Ok/Err constants without namespace prefix
  module Match
    Ok = Dex::Ok
    Err = Dex::Err
  end
end
