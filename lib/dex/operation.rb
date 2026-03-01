# frozen_string_literal: true

# Wrapper modules (loaded before class body so `include`/`use` can find them)
require_relative "operation/settings"
require_relative "operation/props_setup"
require_relative "operation/result_wrapper"
require_relative "operation/record_wrapper"
require_relative "operation/transaction_wrapper"
require_relative "operation/lock_wrapper"
require_relative "operation/async_wrapper"
require_relative "operation/safe_wrapper"
require_relative "operation/rescue_wrapper"
require_relative "operation/callback_wrapper"

# Pipeline (referenced inside class body)
require_relative "operation/pipeline"

module Dex
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

    private_class_method :_dex_resolve_base_class, :_dex_coerce_value, :_dex_find_ref_type, :_dex_coerce_serialized_hash

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
        ref = self.class.send(:_dex_find_ref_type, prop.type)
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
  end
end

# Nested classes (reopen Operation after it's defined)
require_relative "operation/outcome"
require_relative "operation/async_proxy"
require_relative "operation/record_backend"
require_relative "operation/transaction_adapter"
require_relative "operation/jobs"

# Top-level aliases (depend on Operation::Ok/Err)
require_relative "match"
