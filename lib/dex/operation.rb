# frozen_string_literal: true

# Wrapper modules (loaded before class body so `include`/`use` can find them)
require_relative "operation/settings"
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

    RESERVED_PROP_NAMES = %i[call perform async safe initialize].to_set.freeze

    include PropsSetup
    include TypeCoercion

    private_class_method :_find_ref_type, :_resolve_base_class, :_coerce_value,
      :_serialize_value, :_coerce_serialized_hash

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

    include Settings
    include AsyncWrapper
    include SafeWrapper

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
