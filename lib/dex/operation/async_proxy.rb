# frozen_string_literal: true

module Dex
  class Operation
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
  end
end
