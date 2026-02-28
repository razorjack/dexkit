# frozen_string_literal: true

require "set"

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
    def self.included(base)
      base.extend(ClassMethods)
    end

    def _record_wrap
      halted = nil
      result = catch(:_dex_halt) { yield }

      if result.is_a?(Operation::Halt)
        halted = result
        result = halted.success? ? halted.value : nil
      end

      if halted.nil? || halted.success?
        if _record_has_pending_record?
          _record_update_done!(result)
        elsif _record_enabled?
          _record_save!(result)
        end
      end

      throw(:_dex_halt, halted) if halted
      result
    end

    RECORD_KNOWN_OPTIONS = %i[params response].freeze

    module ClassMethods
      def record(enabled = nil, **options)
        unknown = options.keys - RecordWrapper::RECORD_KNOWN_OPTIONS
        if unknown.any?
          raise ArgumentError,
            "unknown record option(s): #{unknown.map(&:inspect).join(", ")}. " \
            "Known: #{RecordWrapper::RECORD_KNOWN_OPTIONS.map(&:inspect).join(", ")}"
        end

        if enabled == false
          set :record, enabled: false
        elsif enabled == true || enabled.nil?
          merged = { enabled: true, params: true, response: true }.merge(options)
          set :record, **merged
        else
          raise ArgumentError,
            "record expects true, false, or nil, got: #{enabled.inspect}"
        end
      end
    end

    private

    def _record_enabled?
      return false unless Dex.record_backend
      return false unless self.class.name

      record_settings = self.class.settings_for(:record)
      record_settings.fetch(:enabled, true)
    end

    def _record_has_pending_record?
      defined?(@_dex_record_id) && @_dex_record_id
    end

    def _record_save!(result)
      Dex.record_backend.create_record(_record_attributes(result))
    rescue => e
      _record_handle_error(e)
    end

    def _record_update_done!(result)
      attrs = { status: "done", performed_at: _record_current_time }
      attrs[:response] = _record_response(result) if _record_response?
      Dex.record_backend.update_record(@_dex_record_id, attrs)
    rescue => e
      _record_handle_error(e)
    end

    def _record_attributes(result)
      attrs = { name: self.class.name, performed_at: _record_current_time, status: "done" }
      attrs[:params] = _record_params? ? _record_params : nil
      attrs[:response] = _record_response? ? _record_response(result) : nil
      attrs
    end

    def _record_params
      _props_as_json
    end

    def _record_params?
      self.class.settings_for(:record).fetch(:params, true)
    end

    def _record_response?
      self.class.settings_for(:record).fetch(:response, true)
    end

    def _record_response(result)
      success_type = self.class.respond_to?(:_success_type) && self.class._success_type

      if success_type
        _record_serialize_typed_result(result, success_type)
      else
        case result
        when nil then nil
        when Hash then result
        else { value: result }
        end
      end
    end

    def _record_serialize_typed_result(result, type)
      return nil if result.nil?

      ref_type = self.class._dex_find_ref_type(type)
      if ref_type && result.respond_to?(:id)
        result.id
      else
        result.respond_to?(:as_json) ? result.as_json : result
      end
    end

    def _record_current_time
      Time.respond_to?(:current) ? Time.current : Time.now
    end

    def _record_handle_error(error)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn "[Dex] Failed to record operation: #{error.message}"
      end
    end
  end

  module TransactionWrapper
    def self.included(base)
      base.extend(ClassMethods)
    end

    def _transaction_wrap
      return yield unless _transaction_enabled?

      halted = nil
      result = _transaction_execute do
        halted_value = catch(:_dex_halt) { yield }
        if halted_value.is_a?(Operation::Halt)
          halted = halted_value
          raise _transaction_adapter.rollback_exception_class if halted.error?
          halted.value
        else
          halted_value
        end
      end

      throw(:_dex_halt, halted) if halted
      result
    end

    TRANSACTION_KNOWN_ADAPTERS = %i[active_record mongoid].freeze
    TRANSACTION_KNOWN_OPTIONS = %i[adapter].freeze

    module ClassMethods
      def transaction(enabled_or_options = nil, **options)
        unknown = options.keys - TransactionWrapper::TRANSACTION_KNOWN_OPTIONS
        if unknown.any?
          raise ArgumentError,
            "unknown transaction option(s): #{unknown.map(&:inspect).join(", ")}. " \
            "Known: #{TransactionWrapper::TRANSACTION_KNOWN_OPTIONS.map(&:inspect).join(", ")}"
        end

        case enabled_or_options
        when false
          set :transaction, enabled: false
        when true, nil
          _transaction_validate_adapter!(options[:adapter]) if options.key?(:adapter)
          set :transaction, enabled: true, **options
        when Symbol
          _transaction_validate_adapter!(enabled_or_options)
          set :transaction, enabled: true, adapter: enabled_or_options, **options
        else
          raise ArgumentError,
            "transaction expects true, false, nil, or a Symbol adapter, got: #{enabled_or_options.inspect}"
        end
      end

      private

      def _transaction_validate_adapter!(adapter)
        return if adapter.nil?

        unless TransactionWrapper::TRANSACTION_KNOWN_ADAPTERS.include?(adapter.to_sym)
          raise ArgumentError,
            "unknown transaction adapter: #{adapter.inspect}. " \
            "Known: #{TransactionWrapper::TRANSACTION_KNOWN_ADAPTERS.map(&:inspect).join(", ")}"
        end
      end
    end

    private

    def _transaction_enabled?
      settings = self.class.settings_for(:transaction)
      settings.fetch(:enabled, true)
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

  module LockWrapper
    def self.included(base)
      base.extend(ClassMethods)
    end

    LOCK_KNOWN_OPTIONS = %i[timeout].freeze

    module ClassMethods
      def advisory_lock(key = nil, **options, &block)
        unknown = options.keys - LockWrapper::LOCK_KNOWN_OPTIONS
        if unknown.any?
          raise ArgumentError,
            "unknown advisory_lock option(s): #{unknown.map(&:inspect).join(", ")}. " \
            "Known: #{LockWrapper::LOCK_KNOWN_OPTIONS.map(&:inspect).join(", ")}"
        end

        lock_key = block || key

        unless lock_key.nil? || lock_key.is_a?(String) || lock_key.is_a?(Symbol) || lock_key.is_a?(Proc)
          raise ArgumentError, "advisory_lock key must be a String, Symbol, or Proc, got: #{lock_key.class}"
        end

        if options.key?(:timeout) && !options[:timeout].is_a?(Numeric)
          raise ArgumentError, "advisory_lock :timeout must be Numeric, got: #{options[:timeout].inspect}"
        end

        set(:advisory_lock, enabled: true, key: lock_key, **options)
      end
    end

    def _lock_wrap
      _lock_enabled? ? _lock_execute { yield } : yield
    end

    private

    def _lock_enabled?
      self.class.settings_for(:advisory_lock).fetch(:enabled, false)
    end

    def _lock_key
      key = self.class.settings_for(:advisory_lock)[:key]
      case key
      when String then key
      when Symbol then send(key)
      when Proc then instance_exec(&key)
      when nil then self.class.name || raise(ArgumentError, "Anonymous classes must provide an explicit lock key")
      else raise ArgumentError, "Unsupported advisory_lock key type: #{key.class}"
      end
    end

    def _lock_options
      opts = {}
      timeout = self.class.settings_for(:advisory_lock)[:timeout]
      opts[:timeout_seconds] = timeout if timeout
      opts
    end

    def _lock_execute(&block)
      _lock_ensure_loaded!
      key = _lock_key
      ActiveRecord::Base.with_advisory_lock!(key, **_lock_options, &block)
    rescue WithAdvisoryLock::FailedToAcquireLock
      raise Dex::Error.new(:lock_timeout, "Could not acquire advisory lock: #{key}")
    end

    def _lock_ensure_loaded!
      return if ActiveRecord::Base.respond_to?(:with_advisory_lock!)

      raise LoadError,
        "with_advisory_lock gem is required for advisory locking. Add 'with_advisory_lock' to your Gemfile."
    end
  end

  module PropsSetup
    def self.included(base)
      base.extend(Literal::Properties)
      base.extend(Literal::Types)
      base.extend(ClassMethods)
    end

    module ClassMethods
      RESERVED_PROP_NAMES = %i[call perform async safe initialize].to_set.freeze

      def prop(name, type, kind = :keyword, **options, &block)
        _props_validate_name!(name)
        options[:reader] = :public unless options.key?(:reader)
        if type.is_a?(Dex::RefType) && !block
          ref = type
          block = ->(v) { ref.coerce(v) }
        end
        super(name, type, kind, **options, &block)
      end

      def prop?(name, type, kind = :keyword, **options, &block)
        options[:reader] = :public unless options.key?(:reader)
        options[:default] = nil unless options.key?(:default)
        if type.is_a?(Dex::RefType) && !block
          ref = type
          block = ->(v) { v.nil? ? v : ref.coerce(v) }
        end
        prop(name, _Nilable(type), kind, **options, &block)
      end

      def _Ref(model_class, lock: false) # rubocop:disable Naming/MethodName
        Dex::RefType.new(model_class, lock: lock)
      end

      private

      def _props_validate_name!(name)
        return unless RESERVED_PROP_NAMES.include?(name)

        raise ArgumentError,
          "Property :#{name} conflicts with core Operation methods."
      end
    end
  end

  module ResultWrapper
    module ClassMethods
      def success(type)
        @_success_type = type
      end

      def error(*codes)
        invalid = codes.reject { |c| c.is_a?(Symbol) }
        if invalid.any?
          raise ArgumentError, "error codes must be Symbols, got: #{invalid.map(&:inspect).join(", ")}"
        end

        @_declared_errors ||= []
        @_declared_errors.concat(codes)
      end

      def _success_type
        @_success_type || (superclass.respond_to?(:_success_type) ? superclass._success_type : nil)
      end

      def _declared_errors
        parent = superclass.respond_to?(:_declared_errors) ? superclass._declared_errors : []
        own = @_declared_errors || []
        (parent + own).uniq
      end

      def _has_declared_errors?
        _declared_errors.any?
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def _result_wrap
      halted = catch(:_dex_halt) { yield }
      if halted.is_a?(Operation::Halt)
        if halted.success?
          _result_validate_success_type!(halted.value)
          halted.value
        else
          raise Dex::Error.new(halted.error_code, halted.error_message, details: halted.error_details)
        end
      else
        _result_validate_success_type!(halted)
        halted
      end
    end

    def error!(code, message = nil, details: nil)
      if self.class._has_declared_errors? && !self.class._declared_errors.include?(code)
        raise ArgumentError, "Undeclared error code: #{code.inspect}. Declared: #{self.class._declared_errors.inspect}"
      end

      throw(:_dex_halt, Operation::Halt.new(type: :error, error_code: code, error_message: message,
        error_details: details))
    end

    def success!(value = nil, **attrs)
      throw(:_dex_halt, Operation::Halt.new(type: :success, value: attrs.empty? ? value : attrs))
    end

    def assert!(* args, &block)
      if block
        code = args[0]
        value = yield
      else
        value, code = args
      end

      error!(code) unless value
      value
    end

    private

    def _result_validate_success_type!(value)
      return if value.nil?

      success_type = self.class._success_type
      return unless success_type
      return if success_type === value

      raise ArgumentError,
        "#{self.class.name || "Operation"} declared `success #{success_type.inspect}` but returned #{value.class}"
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

    def self.included(base)
      base.extend(ClassMethods)
    end
  end

  module AsyncWrapper
    ASYNC_KNOWN_OPTIONS = %i[queue in at].freeze

    module ClassMethods
      def async(**options)
        unknown = options.keys - AsyncWrapper::ASYNC_KNOWN_OPTIONS
        if unknown.any?
          raise ArgumentError,
            "unknown async option(s): #{unknown.map(&:inspect).join(", ")}. " \
            "Known: #{AsyncWrapper::ASYNC_KNOWN_OPTIONS.map(&:inspect).join(", ")}"
        end

        set(:async, **options)
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def async(**options)
      unknown = options.keys - AsyncWrapper::ASYNC_KNOWN_OPTIONS
      if unknown.any?
        raise ArgumentError,
          "unknown async option(s): #{unknown.map(&:inspect).join(", ")}. " \
          "Known: #{AsyncWrapper::ASYNC_KNOWN_OPTIONS.map(&:inspect).join(", ")}"
      end

      Operation::AsyncProxy.new(self, **options)
    end
  end

  module SafeWrapper
    def safe
      Operation::SafeProxy.new(self)
    end
  end

  module RescueWrapper
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def rescue_from(*exception_classes, as:, message: nil)
        raise ArgumentError, "rescue_from requires at least one exception class" if exception_classes.empty?

        invalid = exception_classes.reject { |k| k.is_a?(Module) && k <= Exception }
        if invalid.any?
          raise ArgumentError,
            "rescue_from expects Exception subclasses, got: #{invalid.map(&:inspect).join(", ")}"
        end

        raise ArgumentError, "rescue_from :as must be a Symbol, got: #{as.inspect}" unless as.is_a?(Symbol)

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

    def _rescue_wrap
      yield
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
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def before(callable = nil, &block)
        _callback_validate!(callable, block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:before) << entry
      end

      def after(callable = nil, &block)
        _callback_validate!(callable, block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:after) << entry
      end

      def around(callable = nil, &block)
        _callback_validate!(callable, block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:around) << entry
      end

      def _callback_list(type)
        parent_callbacks = superclass.respond_to?(:_callback_list) ? superclass._callback_list(type) : []
        parent_callbacks + _callback_own(type)
      end

      def _callback_any?
        %i[before after around].any? { |type| _callback_list(type).any? }
      end

      private

      def _callback_validate!(callable, block)
        return if callable.is_a?(Symbol)
        return if callable.nil? && block
        return if callable.respond_to?(:call)

        if callable.nil?
          raise ArgumentError, "callback requires a Symbol, callable, or block"
        else
          raise ArgumentError, "callback must be a Symbol or callable, got: #{callable.class}"
        end
      end

      def _callback_own(type)
        @_callbacks ||= { before: [], after: [], around: [] }
        @_callbacks[type]
      end
    end

    def _callback_wrap
      return yield unless self.class._callback_any?

      halted = nil
      result = _callback_run_around(self.class._callback_list(:around)) do
        _callback_run_before
        caught = catch(:_dex_halt) { yield }
        if caught.is_a?(Operation::Halt)
          if caught.success?
            halted = caught
            _callback_run_after
            caught.value
          else
            throw(:_dex_halt, caught)
          end
        else
          _callback_run_after
          caught
        end
      end
      throw(:_dex_halt, halted) if halted
      result
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
    Halt = Struct.new(:type, :value, :error_code, :error_message, :error_details, keyword_init: true) do
      def success? = type == :success
      def error? = type == :error
    end

    def self._serialized_coercions
      @_serialized_coercions ||= {
        Time => ->(v) { v.is_a?(String) ? Time.parse(v) : v },
        Symbol => ->(v) { v.is_a?(String) ? v.to_sym : v }
      }.tap do |h|
        h[Date] = ->(v) { v.is_a?(String) ? Date.parse(v) : v } if defined?(Date)
        h[DateTime] = ->(v) { v.is_a?(String) ? DateTime.parse(v) : v } if defined?(DateTime)
        h[BigDecimal] = ->(v) { v.is_a?(String) ? BigDecimal(v) : v } if defined?(BigDecimal)
      end.freeze
    end

    Contract = Data.define(:params, :success, :errors)

    def self.contract
      Contract.new(
        params: _contract_params,
        success: _success_type,
        errors: _declared_errors
      )
    end

    def self._contract_params
      return {} unless respond_to?(:literal_properties)

      literal_properties.each_with_object({}) do |prop, hash|
        hash[prop.name] = prop.type
      end
    end

    private_class_method :_contract_params

    def self._dex_find_ref_type(type)
      return type if type.is_a?(Dex::RefType)

      if type.respond_to?(:type)
        inner = type.type
        return inner if inner.is_a?(Dex::RefType)
      end
      nil
    end

    def self._dex_coerce_serialized_hash(hash)
      return hash.transform_keys(&:to_sym) unless respond_to?(:literal_properties)

      result = {}
      literal_properties.each do |prop|
        name = prop.name
        raw = hash.key?(name) ? hash[name] : hash[name.to_s]
        result[name] = _dex_coerce_value(prop.type, raw)
      end
      result
    end

    def self._dex_resolve_base_class(type)
      return type.model_class if type.is_a?(Dex::RefType)
      return _dex_resolve_base_class(type.type) if type.respond_to?(:type)

      type if type.is_a?(Class)
    end

    def self._dex_coerce_value(type, value)
      return value unless value
      return value if _dex_find_ref_type(type)

      if type.respond_to?(:type) && type.is_a?(Literal::Types::ArrayType)
        return value.map { |v| _dex_coerce_value(type.type, v) } if value.is_a?(Array)
        return value
      end

      if type.respond_to?(:type) && type.is_a?(Literal::Types::NilableType)
        return _dex_coerce_value(type.type, value)
      end

      base = _dex_resolve_base_class(type)
      coercion = _serialized_coercions[base]
      coercion ? coercion.call(value) : value
    end

    private_class_method :_dex_resolve_base_class, :_dex_coerce_value

    def self.inherited(subclass)
      subclass.instance_variable_set(:@_pipeline, pipeline.dup)
      super
    end

    def self.pipeline
      @_pipeline ||= Pipeline.new
    end

    def self.use(mod, as: nil, wrap: nil, before: nil, after: nil, at: nil)
      step_name = as || _derive_step_name(mod)
      wrap_method = wrap || :"_#{step_name}_wrap"
      pipeline.add(step_name, method: wrap_method, before: before, after: after, at: at)
      include mod
    end

    def self._derive_step_name(mod)
      base = mod.name&.split("::")&.last
      raise ArgumentError, "anonymous modules require explicit as: parameter" unless base

      base.sub(/Wrapper\z/, "")
        .gsub(/([a-z])([A-Z])/, '\1_\2')
        .downcase
        .to_sym
    end
    private_class_method :_derive_step_name

    class Pipeline
      Step = Data.define(:name, :method)

      def initialize(steps = [])
        @steps = steps.dup
      end

      def dup
        self.class.new(@steps)
      end

      def steps
        @steps.dup.freeze
      end

      def add(name, method: :"_#{name}_wrap", before: nil, after: nil, at: nil)
        _validate_positioning!(before, after, at)
        step = Step.new(name: name, method: method)

        if at == :outer then @steps.unshift(step)
        elsif at == :inner then @steps.push(step)
        elsif before then @steps.insert(_find_index!(before), step)
        elsif after then @steps.insert(_find_index!(after) + 1, step)
        else @steps.push(step)
        end
        self
      end

      def remove(name)
        @steps.reject! { |s| s.name == name }
        self
      end

      def execute(operation)
        chain = @steps.reverse_each.reduce(-> { yield }) do |next_step, step|
          -> { operation.send(step.method, &next_step) }
        end
        chain.call
      end

      private

      def _validate_positioning!(before, after, at)
        count = [before, after, at].count { |v| !v.nil? }
        raise ArgumentError, "specify only one of before:, after:, at:" if count > 1
        raise ArgumentError, "at: must be :outer or :inner" if at && !%i[outer inner].include?(at)
      end

      def _find_index!(name)
        idx = @steps.index { |s| s.name == name }
        raise ArgumentError, "pipeline step :#{name} not found" unless idx
        idx
      end
    end

    def perform(*, **)
    end

    def call
      self.class.pipeline.execute(self) { perform }
    end

    def self.method_added(method_name)
      super
      return unless method_name == :perform

      private :perform
    end

    private :perform

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # Serialization helpers

    def _props_as_json
      return {} unless self.class.respond_to?(:literal_properties)

      result = {}
      self.class.literal_properties.each do |prop|
        value = public_send(prop.name)
        ref = self.class._dex_find_ref_type(prop.type)
        result[prop.name.to_s] = if ref && value
          value.id
        else
          value.respond_to?(:as_json) ? value.as_json : value
        end
      end
      result
    end

    include Settings
    include AsyncWrapper
    include SafeWrapper
    include PropsSetup

    use ResultWrapper
    use LockWrapper
    use TransactionWrapper
    use RecordWrapper
    use RescueWrapper
    use CallbackWrapper

    class AsyncProxy
      def initialize(operation, **runtime_options)
        @operation = operation
        @runtime_options = runtime_options
      end

      def call
        _async_ensure_active_job_loaded!
        if _async_use_record_strategy?
          _async_enqueue_record_job
        else
          _async_enqueue_direct_job
        end
      end

      private

      def _async_enqueue_direct_job
        job = _async_apply_options(Operation::DirectJob)
        job.perform_later(class_name: _async_operation_class_name, params: _async_serialized_params)
      end

      def _async_enqueue_record_job
        record = Dex.record_backend.create_record(
          name: _async_operation_class_name,
          params: _async_serialized_params,
          status: "pending"
        )
        begin
          job = _async_apply_options(Operation::RecordJob)
          job.perform_later(class_name: _async_operation_class_name, record_id: record.id)
        rescue => e
          begin
            record.destroy
          rescue => destroy_error
            _async_log_warning("Failed to clean up pending record #{record.id}: #{destroy_error.message}")
          end
          raise e
        end
      end

      def _async_use_record_strategy?
        return false unless Dex.record_backend
        return false unless @operation.class.name

        record_settings = @operation.class.settings_for(:record)
        return false if record_settings[:enabled] == false
        return false if record_settings[:params] == false

        true
      end

      def _async_apply_options(job_class)
        options = {}
        options[:queue] = _async_queue if _async_queue
        options[:wait_until] = _async_scheduled_at if _async_scheduled_at
        options[:wait] = _async_scheduled_in if _async_scheduled_in
        options.empty? ? job_class : job_class.set(**options)
      end

      def _async_ensure_active_job_loaded!
        return if defined?(ActiveJob::Base)

        raise LoadError, "ActiveJob is required for async operations. Add 'activejob' to your Gemfile."
      end

      def _async_merged_options
        @operation.class.settings_for(:async).merge(@runtime_options)
      end

      def _async_queue = _async_merged_options[:queue]
      def _async_scheduled_at = _async_merged_options[:at]
      def _async_scheduled_in = _async_merged_options[:in]
      def _async_operation_class_name = @operation.class.name

      def _async_serialized_params
        @_async_serialized_params ||= begin
          hash = @operation._props_as_json
          _async_validate_serializable!(hash)
          hash
        end
      end

      def _async_log_warning(message)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn "[Dex] #{message}"
        end
      end

      def _async_validate_serializable!(hash, path: "")
        hash.each do |key, value|
          current = path.empty? ? key.to_s : "#{path}.#{key}"
          case value
          when String, Integer, Float, NilClass, TrueClass, FalseClass
            next
          when Hash
            _async_validate_serializable!(value, path: current)
          when Array
            value.each_with_index do |v, i|
              _async_validate_serializable!({ i => v }, path: current)
            end
          else
            raise ArgumentError,
              "Param '#{current}' (#{value.class}) is not JSON-serializable. " \
              "Async operations require all params to be serializable."
          end
        end
      end
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

      def call
        result = @operation.call
        Operation::Ok.new(result)
      rescue Dex::Error => e
        Operation::Err.new(e)
      end
    end

    # Job classes are defined lazily when ActiveJob is loaded
    def self.const_missing(name)
      return super unless defined?(ActiveJob::Base)

      case name
      when :DirectJob
        const_set(:DirectJob, Class.new(ActiveJob::Base) do
          def perform(class_name:, params:)
            klass = class_name.constantize
            klass.new(**klass._dex_coerce_serialized_hash(params)).call
          end
        end)
      when :RecordJob
        const_set(:RecordJob, Class.new(ActiveJob::Base) do
          def perform(class_name:, record_id:)
            klass = class_name.constantize
            record = Dex.record_backend.find_record(record_id)
            params = klass._dex_coerce_serialized_hash(record.params || {})

            op = klass.new(**params)
            op.instance_variable_set(:@_dex_record_id, record_id)

            _dex_update_status(record_id, status: "running")
            op.call
          rescue => e
            _dex_handle_failure(record_id, e)
            raise
          end

          private

          def _dex_update_status(record_id, **attributes)
            Dex.record_backend.update_record(record_id, attributes)
          rescue => e
            _dex_log_warning("Failed to update record status: #{e.message}")
          end

          def _dex_handle_failure(record_id, exception)
            error_value = if exception.is_a?(Dex::Error)
              exception.code.to_s
            else
              exception.class.name
            end
            _dex_update_status(record_id, status: "failed", error: error_value)
          end

          def _dex_log_warning(message)
            if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
              Rails.logger.warn "[Dex] #{message}"
            end
          end
        end)
      when :Job
        const_set(:Job, const_get(:DirectJob))
      else
        super
      end
    end

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

  # Top-level aliases for clean pattern matching
  Ok = Operation::Ok
  Err = Operation::Err

  # Module for including Ok/Err constants without namespace prefix
  module Match
    Ok = Dex::Ok
    Err = Dex::Err
  end
end
