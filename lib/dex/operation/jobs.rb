# frozen_string_literal: true

module Dex
  class Operation
    # Job classes are defined lazily when ActiveJob is loaded
    def self.const_missing(name)
      return super unless defined?(ActiveJob::Base)

      case name
      when :DirectJob
        const_set(:DirectJob, Class.new(ActiveJob::Base) do
          def perform(class_name:, params:, trace: nil, once_key: nil, once_bypass: false)
            klass = class_name.constantize
            op = klass.new(**klass.send(:_coerce_serialized_hash, params))
            op.once(once_key) if once_key
            op.once(nil) if once_bypass
            Dex::Trace.restore(trace) { op.call }
          end
        end)
      when :RecordJob
        const_set(:RecordJob, Class.new(ActiveJob::Base) do
          def perform(class_name:, record_id:, trace: nil, once_key: nil, once_bypass: false)
            klass = class_name.constantize
            record = Dex.record_backend.find_record(record_id)
            params = klass.send(:_coerce_serialized_hash, record.params || {})

            op = klass.new(**params)
            op.instance_variable_set(:@_dex_record_id, record_id)
            op.instance_variable_set(:@_dex_execution_id, record_id)
            op.once(once_key) if once_key
            op.once(nil) if once_bypass

            update_status(record_id, status: "running")
            pipeline_started = true
            Dex::Trace.restore(trace) { op.call }
          rescue => e
            # RecordWrapper handles failures during op.call via its own rescue.
            # This catches pre-pipeline failures (find_record, deserialization, etc.)
            mark_failed(record_id, e) unless pipeline_started
            raise
          end

          private

          def update_status(record_id, **attributes)
            Dex.record_backend.update_record(record_id, attributes)
          rescue => e
            Dex.warn("Failed to update record status: #{e.message}")
          end

          def mark_failed(record_id, exception)
            update_status(record_id,
              status: "failed",
              error_code: exception.class.name,
              error_message: exception.message,
              performed_at: Time.respond_to?(:current) ? Time.current : Time.now)
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
