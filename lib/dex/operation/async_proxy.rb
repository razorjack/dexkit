# frozen_string_literal: true

module Dex
  class Operation
    class AsyncProxy
      def initialize(operation, **runtime_options)
        @operation = operation
        @runtime_options = runtime_options
      end

      def call
        ensure_active_job_loaded!
        if use_record_strategy?
          enqueue_record_job
        else
          enqueue_direct_job
        end
      end

      private

      def enqueue_direct_job
        job = apply_options(Operation::DirectJob)
        payload = {
          class_name: operation_class_name,
          params: serialized_params,
          trace: Dex::Trace.dump
        }
        apply_once_payload!(payload)
        job.perform_later(**payload)
      end

      def enqueue_record_job
        @operation.send(:_record_validate_backend!, async: true)
        execution_id = Dex::Id.generate("op_")
        record = Dex.record_backend.create_record(
          id: execution_id,
          name: operation_class_name,
          params: serialized_params,
          status: "pending"
        )
        begin
          job = apply_options(Operation::RecordJob)
          payload = {
            class_name: operation_class_name,
            record_id: record.id.to_s,
            trace: Dex::Trace.dump
          }
          apply_once_payload!(payload)
          job.perform_later(**payload)
        rescue => e
          begin
            record.destroy
          rescue => destroy_error
            Dex.warn("Failed to clean up pending record #{record.id}: #{destroy_error.message}")
          end
          raise e
        end
      end

      def use_record_strategy?
        return false unless Dex.record_backend
        return false unless @operation.class.name

        record_settings = @operation.class.settings_for(:record)
        return false if record_settings[:enabled] == false
        return false if record_settings[:params] == false

        true
      end

      def apply_options(job_class)
        options = {}
        options[:queue] = queue if queue
        options[:wait_until] = scheduled_at if scheduled_at
        options[:wait] = scheduled_in if scheduled_in
        options.empty? ? job_class : job_class.set(**options)
      end

      def ensure_active_job_loaded!
        return if defined?(ActiveJob::Base)

        raise LoadError, "ActiveJob is required for async operations. Add 'activejob' to your Gemfile."
      end

      def apply_once_payload!(payload)
        return unless @operation.instance_variable_defined?(:@_once_key_explicit) &&
          @operation.instance_variable_get(:@_once_key_explicit)

        once_key = @operation.instance_variable_get(:@_once_key)
        if once_key
          payload[:once_key] = once_key
        else
          payload[:once_bypass] = true
        end
      end

      def merged_options
        @operation.class.settings_for(:async).merge(@runtime_options)
      end

      def queue = merged_options[:queue]
      def scheduled_at = merged_options[:at]
      def scheduled_in = merged_options[:in]
      def operation_class_name = @operation.class.name

      def serialized_params
        @serialized_params ||= begin
          hash = @operation._props_as_json
          validate_serializable!(hash)
          hash
        end
      end

      def validate_serializable!(hash, path: "")
        hash.each do |key, value|
          current = path.empty? ? key.to_s : "#{path}.#{key}"
          case value
          when String, Integer, Float, NilClass, TrueClass, FalseClass
            next
          when Hash
            validate_serializable!(value, path: current)
          when Array
            value.each_with_index do |v, i|
              validate_serializable!({ i => v }, path: current)
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
