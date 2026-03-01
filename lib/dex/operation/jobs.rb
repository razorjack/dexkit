# frozen_string_literal: true

module Dex
  class Operation
    # Job classes are defined lazily when ActiveJob is loaded
    def self.const_missing(name)
      return super unless defined?(ActiveJob::Base)

      case name
      when :DirectJob
        const_set(:DirectJob, Class.new(ActiveJob::Base) do
          def perform(class_name:, params:)
            klass = class_name.constantize
            klass.new(**klass.send(:_dex_coerce_serialized_hash, params)).call
          end
        end)
      when :RecordJob
        const_set(:RecordJob, Class.new(ActiveJob::Base) do
          def perform(class_name:, record_id:)
            klass = class_name.constantize
            record = Dex.record_backend.find_record(record_id)
            params = klass.send(:_dex_coerce_serialized_hash, record.params || {})

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
  end
end
