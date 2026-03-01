# frozen_string_literal: true

module Dex
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

      ref_type = self.class.send(:_dex_find_ref_type, type)
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
end
