# frozen_string_literal: true

module Dex
  module RecordWrapper
    extend Dex::Concern

    def _record_wrap
      interceptor = Operation::HaltInterceptor.new { yield }

      if interceptor.success?
        if _record_has_pending_record?
          _record_update_done!(interceptor.result)
        elsif _record_enabled?
          _record_save!(interceptor.result)
        end
      end

      interceptor.rethrow!
      interceptor.result
    end

    module ClassMethods
      def record(enabled = nil, **options)
        validate_options!(options, %i[params response], :record)

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
        result.nil? ? nil : self.class.send(:_serialize_value, success_type, result)
      else
        case result
        when nil then nil
        when Hash then result
        else { value: result }
        end
      end
    end

    def _record_current_time
      Time.respond_to?(:current) ? Time.current : Time.now
    end

    def _record_handle_error(error)
      Dex.warn("Failed to record operation: #{error.message}")
    end
  end
end
