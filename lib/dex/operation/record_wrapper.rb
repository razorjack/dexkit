# frozen_string_literal: true

module Dex
  module RecordWrapper
    extend Dex::Concern

    def _record_wrap
      _record_validate_backend! if _record_enabled? || _record_has_pending_record?
      interceptor = Operation::HaltInterceptor.new { yield }

      if _record_has_pending_record?
        _record_update_outcome!(interceptor)
      elsif _record_enabled?
        _record_save!(interceptor)
      end

      interceptor.rethrow!
      interceptor.result
    rescue => e
      _record_failure!(e) if _record_has_pending_record? || _record_enabled?
      raise
    end

    module ClassMethods
      def record(enabled = nil, **options)
        validate_options!(options, %i[params result], :record)

        if enabled == false
          set :record, enabled: false
        elsif enabled == true || enabled.nil?
          merged = { enabled: true, params: true, result: true }.merge(options)
          set :record, **merged
        else
          raise ArgumentError,
            "record expects true, false, or nil, got: #{enabled.inspect}"
        end
      end

      def _record_required_fields(async: false)
        settings = settings_for(:record)
        fields = %w[name status performed_at error_code error_message error_details]
        fields << "params" if async || settings.fetch(:params, true)
        fields << "result" if settings.fetch(:result, true)
        fields
      end
    end

    private

    def _record_enabled?
      return false unless Dex.record_backend
      return false unless self.class.name

      record_settings = self.class.settings_for(:record)
      record_settings.fetch(:enabled, true)
    end

    def _record_validate_backend!(async: false)
      Dex.record_backend.ensure_fields!(
        self.class.send(:_record_required_fields, async: async),
        feature: async ? "async recording" : "operation recording"
      )
    end

    def _record_has_pending_record?
      defined?(@_dex_record_id) && @_dex_record_id
    end

    def _record_save!(interceptor)
      attrs = _record_base_attrs
      if interceptor.error?
        attrs.merge!(_record_error_attrs(code: interceptor.halt.error_code,
          message: interceptor.halt.error_message,
          details: interceptor.halt.error_details))
      else
        attrs.merge!(_record_success_attrs(interceptor.result))
      end
      Dex.record_backend.create_record(attrs)
    rescue => e
      _record_handle_error(e)
    end

    def _record_update_outcome!(interceptor)
      attrs = if interceptor.error?
        _record_error_attrs(code: interceptor.halt.error_code,
          message: interceptor.halt.error_message,
          details: interceptor.halt.error_details)
      else
        _record_success_attrs(interceptor.result)
      end
      Dex.record_backend.update_record(@_dex_record_id, attrs)
    rescue => e
      _record_handle_error(e)
    end

    def _record_failure!(exception)
      attrs = if exception.is_a?(Dex::Error)
        _record_error_attrs(code: exception.code, message: exception.message, details: exception.details)
      else
        {
          status: "failed",
          error_code: exception.class.name,
          error_message: exception.message,
          performed_at: _record_current_time
        }
      end

      attrs[:once_key] = nil if defined?(@_once_key) || self.class.settings_for(:once).fetch(:defined, false)

      if _record_has_pending_record?
        Dex.record_backend.update_record(@_dex_record_id, attrs)
      else
        Dex.record_backend.create_record(_record_base_attrs.merge(attrs))
      end
    rescue => e
      _record_handle_error(e)
    end

    def _record_base_attrs
      attrs = { name: self.class.name }
      attrs[:params] = _record_params? ? _record_params : nil
      attrs
    end

    def _record_success_attrs(result)
      attrs = { status: "completed", performed_at: _record_current_time }
      attrs[:result] = _record_result(result) if _record_result?
      attrs
    end

    def _record_error_attrs(code:, message:, details:)
      {
        status: "error",
        error_code: code.to_s,
        error_message: message || code.to_s,
        error_details: _record_sanitize_details(details),
        performed_at: _record_current_time
      }
    end

    def _record_params
      _props_as_json
    end

    def _record_params?
      self.class.settings_for(:record).fetch(:params, true)
    end

    def _record_result?
      self.class.settings_for(:record).fetch(:result, true)
    end

    def _record_result(result)
      success_type = self.class.respond_to?(:_success_type) && self.class._success_type

      if success_type
        result.nil? ? nil : self.class.send(:_serialize_value, success_type, result)
      else
        case result
        when nil then nil
        when Hash then _record_sanitize_value(result)
        else { "_dex_value" => _record_sanitize_value(result) } # namespaced key so replay can distinguish wrapped primitives from user hashes
        end
      end
    end

    def _record_current_time
      Time.respond_to?(:current) ? Time.current : Time.now
    end

    def _record_sanitize_details(details)
      _record_sanitize_value(details)
    end

    def _record_sanitize_value(value)
      case value
      when NilClass, String, Integer, Float, TrueClass, FalseClass then value
      when Symbol then value.to_s
      when Hash
        value.each_with_object({}) do |(key, nested_value), result|
          result[key.to_s] = _record_sanitize_value(nested_value)
        end
      when Array then value.map { |v| _record_sanitize_value(v) }
      when Exception then "#{value.class}: #{value.message}"
      else
        if value.respond_to?(:as_json)
          serialized = value.as_json
          return _record_sanitize_value(serialized) unless serialized.equal?(value)
        end

        value.to_s
      end
    end

    def _record_handle_error(error)
      Dex.warn("Failed to record operation: #{error.message}")
    end
  end
end
