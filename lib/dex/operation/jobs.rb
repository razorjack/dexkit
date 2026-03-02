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
            klass.new(**klass.send(:_coerce_serialized_hash, params)).call
          end
        end)
      when :RecordJob
        const_set(:RecordJob, Class.new(ActiveJob::Base) do
          def perform(class_name:, record_id:)
            klass = class_name.constantize
            record = Dex.record_backend.find_record(record_id)
            params = klass.send(:_coerce_serialized_hash, record.params || {})

            op = klass.new(**params)
            op.instance_variable_set(:@_dex_record_id, record_id)

            update_status(record_id, status: "running")
            op.call
          rescue => e
            handle_failure(record_id, e)
            raise
          end

          private

          def update_status(record_id, **attributes)
            Dex.record_backend.update_record(record_id, attributes)
          rescue => e
            Dex.warn("Failed to update record status: #{e.message}")
          end

          def handle_failure(record_id, exception)
            error_value = if exception.is_a?(Dex::Error)
              exception.code.to_s
            else
              exception.class.name
            end
            update_status(record_id, status: "failed", error: error_value)
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
