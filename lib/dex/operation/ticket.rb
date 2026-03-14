# frozen_string_literal: true

module Dex
  class Operation
    class Ticket
      WAIT_MAX_RECOMMENDED = 10

      attr_reader :record, :job

      def initialize(record:, job:)
        @record = record
        @job = job
      end

      def self.from_record(record)
        raise ArgumentError, "from_record requires a record, got nil" unless record

        new(record: record, job: nil)
      end

      # --- Delegated accessors ---

      def id
        _require_record!("id")
        record.id
      end

      def operation_name
        _require_record!("operation_name")
        record.name
      end

      def status
        _require_record!("status")
        record.status
      end

      def error_code
        _require_record!("error_code")
        record.error_code
      end

      def error_message
        _require_record!("error_message")
        record.error_message
      end

      def error_details
        _require_record!("error_details")
        record.error_details
      end

      # --- Predicates ---

      def completed?
        status == "completed"
      end

      def error?
        status == "error"
      end

      def failed?
        status == "failed"
      end

      def pending?
        status == "pending"
      end

      def running?
        status == "running"
      end

      def terminal?
        completed? || error? || failed?
      end

      def recorded?
        !record.nil?
      end

      # --- Reload ---

      def reload
        _require_record!("reload")
        @record = Dex.record_backend.find_record(record.id)
        self
      end

      # --- Outcome reconstruction ---

      def outcome
        _require_record!("outcome")

        case status
        when "completed"
          value = _unwrap_result(record.result)
          value = _coerce_typed_result(value)
          Ok.new(_symbolize_keys(value))
        when "error"
          code = record.error_code&.to_sym
          message = record.error_message
          details = record.error_details
          details = _symbolize_keys(details) if details.is_a?(Hash)
          Err.new(Dex::Error.new(code, message, details: details))
        end
      end

      # --- Wait ---

      def wait(timeout, interval: 0.2)
        _validate_wait_args!(timeout, interval)

        if timeout.to_f > WAIT_MAX_RECOMMENDED
          Dex.warn(
            "Ticket#wait called with #{timeout}s timeout. " \
            "Speculative sync is designed for short waits (under #{WAIT_MAX_RECOMMENDED}s). " \
            "Consider client-side polling for long-running operations."
          )
        end

        interval_fn = interval.respond_to?(:call) ? interval : ->(_) { interval }
        deadline = _monotonic_now + timeout.to_f
        attempt = 0

        loop do
          if terminal?
            result = outcome
            raise _build_operation_failed unless result
            return result
          end

          remaining = deadline - _monotonic_now
          return nil if remaining <= 0

          pause = [interval_fn.call(attempt).to_f, 0.01].max
          sleep [pause, remaining].min
          attempt += 1
          reload
        end
      end

      def wait!(timeout, **opts)
        result = wait(timeout, **opts)
        raise Dex::Timeout.new(timeout: timeout, ticket_id: id, operation_name: operation_name) unless result
        return result.value if result.ok?

        raise result.error
      end

      # --- to_param ---

      def to_param
        id.to_s
      end

      # --- as_json ---

      def as_json(*)
        _require_record!("as_json")

        data = { "id" => id.to_s, "name" => operation_name, "status" => status }

        case status
        when "completed"
          result = _unwrap_result(record.result)
          data["result"] = result unless result.nil?
        when "error"
          data["error"] = {
            "code" => record.error_code,
            "message" => record.error_message,
            "details" => record.error_details
          }.compact
        end

        data
      end

      # --- inspect ---

      def inspect
        if record
          "#<Dex::Operation::Ticket #{operation_name} id=#{id.inspect} status=#{status.inspect}>"
        else
          "#<Dex::Operation::Ticket (unrecorded) job=#{job&.class&.name}>"
        end
      end

      private

      def _require_record!(method)
        return if record

        raise ArgumentError,
          "#{method} requires a recorded operation. " \
          "Enable recording with `record true` in your operation, or use `Ticket.from_record` with an existing record."
      end

      def _validate_wait_args!(timeout, interval)
        unless record
          raise ArgumentError,
            "wait requires a recorded operation. Possible causes: " \
            "(1) recording is not enabled — add `record true` to your operation; " \
            "(2) `record params: false` is set — async operations store params in the record to reconstruct " \
            "the operation in the background job, so params: false forces the direct (non-recorded) strategy. " \
            "If you need to avoid storing params (e.g., PII), consider encrypting params at the model level instead."
        end
        unless _valid_duration?(timeout) && timeout.to_f > 0
          raise ArgumentError, "timeout must be a positive Numeric, got: #{timeout.inspect}"
        end
        if !interval.respond_to?(:call) && !(_valid_duration?(interval) && interval.to_f > 0)
          raise ArgumentError, "interval must be a positive number or a callable, got: #{interval.inspect}"
        end
      end

      def _build_operation_failed
        Dex::OperationFailed.new(
          operation_name: record.name || "Unknown",
          exception_class: record.error_code || "Unknown",
          exception_message: record.error_message || "(no message recorded)"
        )
      end

      def _valid_duration?(value)
        return true if value.is_a?(Numeric)
        return true if defined?(ActiveSupport::Duration) && value.is_a?(ActiveSupport::Duration)

        false
      end

      def _coerce_typed_result(value)
        return value if value.nil?

        klass = record.name&.safe_constantize
        return value unless klass

        success_type = klass.respond_to?(:_success_type) && klass._success_type
        return value unless success_type

        klass.send(:_coerce_value, success_type, value)
      rescue
        value
      end

      def _unwrap_result(result)
        return result unless result.is_a?(Hash) && result.key?("_dex_value")

        result["_dex_value"]
      end

      def _symbolize_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), h| h[k.to_sym] = _symbolize_keys(v) }
        when Array
          value.map { |v| _symbolize_keys(v) }
        else
          value
        end
      end

      def _monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
