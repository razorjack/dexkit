# frozen_string_literal: true

module Dex
  class Operation
    module TestHelpers
      # --- Result assertions ---

      def assert_ok(result, expected = :_not_given, msg = nil, &block)
        assert result.ok?, msg || "Expected Ok, got Err:\n#{_dex_format_err(result)}"
        if expected != :_not_given
          assert_equal expected, result.value, msg || "Ok value mismatch"
        end
        yield result.value if block
        result
      end

      def refute_ok(result, msg = nil)
        refute result.ok?, msg || "Expected Err, got Ok:\n#{_dex_format_ok(result)}"
        result
      end

      def assert_err(result, code = nil, message: nil, details: nil, msg: nil, &block)
        assert result.error?, msg || "Expected Err, got Ok:\n#{_dex_format_ok(result)}"
        if code
          assert_equal code, result.code, msg || "Error code mismatch.\n#{_dex_format_err(result)}"
        end
        if message
          case message
          when Regexp
            assert_match message, result.message, msg || "Error message mismatch.\n#{_dex_format_err(result)}"
          else
            assert_equal message, result.message, msg || "Error message mismatch.\n#{_dex_format_err(result)}"
          end
        end
        details&.each do |key, val|
          assert_equal val, result.details&.dig(key),
            msg || "Error details[:#{key}] mismatch.\n#{_dex_format_err(result)}"
        end
        yield result.error if block
        result
      end

      def refute_err(result, code = nil, msg: nil)
        if code
          if result.error?
            refute_equal code, result.code,
              msg || "Expected result to not have error code #{code.inspect}, but it does.\n#{_dex_format_err(result)}"
          end
        else
          refute result.error?, msg || "Expected Ok, got Err:\n#{_dex_format_err(result)}"
        end
        result
      end

      # --- One-liner assertions ---

      def assert_operation(*args, returns: :_not_given, **params)
        klass = _dex_resolve_subject(args)
        result = klass.new(**params).safe.call
        assert result.ok?, "Expected operation to succeed, got Err:\n#{_dex_format_err(result)}"
        if returns != :_not_given
          assert_equal returns, result.value, "Return value mismatch"
        end
        result
      end

      def assert_operation_error(*args, message: nil, details: nil, **params)
        klass, code = _dex_resolve_subject_and_code(args)
        result = klass.new(**params).safe.call
        assert result.error?, "Expected operation to fail, got Ok:\n#{_dex_format_ok(result)}"
        if code
          assert_equal code, result.code, "Error code mismatch.\n#{_dex_format_err(result)}"
        end
        if message
          case message
          when Regexp
            assert_match message, result.message
          else
            assert_equal message, result.message
          end
        end
        details&.each do |key, val|
          assert_equal val, result.details&.dig(key)
        end
        result
      end

      # --- Contract assertions ---

      def assert_params(*args)
        if args.last.is_a?(Hash)
          klass_args, type_hash = _dex_split_class_and_hash(args)
          klass = _dex_resolve_subject(klass_args)
          contract = klass.contract
          type_hash.each do |name, type|
            assert contract.params.key?(name),
              "Expected param #{name.inspect} to be declared on #{klass.name || klass}"
            assert_equal type, contract.params[name],
              "Type mismatch for param #{name.inspect}"
          end
        else
          klass_args, names = _dex_split_class_and_symbols(args)
          klass = _dex_resolve_subject(klass_args)
          contract = klass.contract
          assert_equal names.sort, contract.params.keys.sort,
            "Params mismatch on #{klass.name || klass}.\n  Expected: #{names.sort.inspect}\n  Actual:   #{contract.params.keys.sort.inspect}"
        end
      end

      def assert_accepts_param(*args)
        klass_args, names = _dex_split_class_and_symbols(args)
        klass = _dex_resolve_subject(klass_args)
        contract = klass.contract
        names.each do |name|
          assert contract.params.key?(name),
            "Expected #{klass.name || klass} to accept param #{name.inspect}, but it doesn't.\n  Declared params: #{contract.params.keys.inspect}"
        end
      end

      def assert_success_type(*args)
        klass = if args.first.is_a?(Class) && args.first < Dex::Operation
          args.shift
        else
          _dex_resolve_subject([])
        end
        expected = args.first
        contract = klass.contract
        assert_equal expected, contract.success,
          "Success type mismatch on #{klass.name || klass}"
      end

      def assert_error_codes(*args)
        klass_args, codes = _dex_split_class_and_symbols(args)
        klass = _dex_resolve_subject(klass_args)
        contract = klass.contract
        assert_equal codes.sort, contract.errors.sort,
          "Error codes mismatch on #{klass.name || klass}.\n  Expected: #{codes.sort.inspect}\n  Actual:   #{contract.errors.sort.inspect}"
      end

      def assert_contract(*args, params: nil, success: :_not_given, errors: nil)
        klass = _dex_resolve_subject(args)
        contract = klass.contract

        if params
          case params
          when Array
            assert_equal params.sort, contract.params.keys.sort, "Contract params mismatch"
          when Hash
            params.each do |name, type|
              assert contract.params.key?(name), "Expected param #{name.inspect}"
              assert_equal type, contract.params[name], "Type mismatch for param #{name.inspect}"
            end
          end
        end

        if success != :_not_given
          assert_equal success, contract.success, "Contract success type mismatch"
        end

        if errors
          assert_equal errors.sort, contract.errors.sort, "Contract error codes mismatch"
        end
      end

      # --- Param validation assertions ---

      def assert_invalid_params(*args, **params)
        klass = _dex_resolve_subject(args)
        assert_raises(Literal::TypeError) { klass.new(**params) }
      end

      def assert_valid_params(*args, **params)
        klass = _dex_resolve_subject(args)
        klass.new(**params)
      end

      # --- Async assertions ---

      def assert_enqueues_operation(*args, queue: nil, **params)
        _dex_ensure_active_job_test_helper!
        klass = _dex_resolve_subject(args)
        async_opts = queue ? { queue: queue } : {}
        before_count = enqueued_jobs.size
        klass.new(**params).async(**async_opts).call
        new_jobs = enqueued_jobs[before_count..]
        dex_job = new_jobs.find { |j|
          j[:job] == Dex::Operation::DirectJob || j[:job] == Dex::Operation::RecordJob
        }
        assert dex_job,
          "Expected #{klass.name || klass} to enqueue an async job, but none were enqueued"
      end

      def refute_enqueues_operation(&block)
        _dex_ensure_active_job_test_helper!
        before_count = enqueued_jobs.size
        yield
        after_count = enqueued_jobs.size
        assert_equal before_count, after_count,
          "Expected no operations to be enqueued, but #{after_count - before_count} were"
      end

      # --- Transaction assertions ---

      def assert_rolls_back(model_class, &block)
        count_before = model_class.count
        assert_raises(Dex::Error) { yield }
        assert_equal count_before, model_class.count,
          "Expected transaction to roll back, but #{model_class.name} count changed from #{count_before} to #{model_class.count}"
      end

      def assert_commits(model_class, &block)
        count_before = model_class.count
        yield
        assert count_before < model_class.count,
          "Expected #{model_class.name} count to increase, but it stayed at #{count_before}"
      end

      # --- Guard assertions ---

      def assert_callable(*args, **params)
        klass = _dex_resolve_subject(args)
        result = klass.callable(**params)
        assert result.ok?, "Expected operation to be callable, but guards failed:\n#{_dex_format_err(result)}"
        result
      end

      def refute_callable(*args, **params)
        klass_args, codes = _dex_split_class_and_symbols(args)
        klass = _dex_resolve_subject(klass_args)
        code = codes.first
        result = klass.callable(**params)
        refute result.ok?, "Expected operation to NOT be callable, but all guards passed"
        if code
          failed_codes = result.details.map { |f| f[:guard] }
          assert_includes failed_codes, code,
            "Expected guard :#{code} to fail, but it didn't.\n  Failed guards: #{failed_codes.inspect}"
        end
        result
      end

      # --- Batch assertions ---

      def assert_all_succeed(*args, params_list:)
        klass = _dex_resolve_subject(args)
        results = params_list.map { |p| klass.new(**p).safe.call }
        failures = results.each_with_index.reject { |r, _| r.ok? }
        if failures.any?
          msgs = failures.map { |r, i| "  [#{i}] #{params_list[i].inspect} => #{_dex_format_err(r)}" }
          flunk "Expected all #{results.size} calls to succeed, but #{failures.size} failed:\n#{msgs.join("\n")}"
        end
        results
      end

      def assert_all_fail(*args, code:, params_list:, message: nil, details: nil)
        klass = _dex_resolve_subject(args)
        results = params_list.map { |p| klass.new(**p).safe.call }
        failures = results.each_with_index.reject { |r, _| r.error? && r.code == code }
        if failures.any?
          msgs = failures.map { |r, i|
            status = r.ok? ? "Ok(#{r.value.inspect})" : "Err(#{r.code})"
            "  [#{i}] #{params_list[i].inspect} => #{status}"
          }
          flunk "Expected all #{results.size} calls to fail with #{code.inspect}, but #{failures.size} didn't:\n#{msgs.join("\n")}"
        end
        results.each_with_index do |r, i|
          if message
            case message
            when Regexp
              assert_match message, r.message,
                "Error message mismatch at [#{i}] #{params_list[i].inspect}.\n#{_dex_format_err(r)}"
            else
              assert_equal message, r.message,
                "Error message mismatch at [#{i}] #{params_list[i].inspect}.\n#{_dex_format_err(r)}"
            end
          end
          details&.each do |key, val|
            assert_equal val, r.details&.dig(key),
              "Error details[:#{key}] mismatch at [#{i}] #{params_list[i].inspect}.\n#{_dex_format_err(r)}"
          end
        end
        results
      end

      private

      def _dex_format_err(result)
        return "(not an error)" unless result.respond_to?(:error?) && result.error?

        lines = ["  code: #{result.code.inspect}"]
        lines << "  message: #{result.message.inspect}" if result.message && result.message != result.code.to_s
        lines << "  details: #{result.details.inspect}" if result.details
        lines.join("\n")
      end

      def _dex_format_ok(result)
        return "(not ok)" unless result.respond_to?(:ok?) && result.ok?

        "  value: #{result.value.inspect}"
      end

      def _dex_resolve_subject_and_code(args)
        if args.first.is_a?(Class) && args.first < Dex::Operation
          klass = args.shift
          code = args.shift
          [klass, code]
        elsif args.first.is_a?(Symbol)
          [_dex_resolve_subject([]), args.shift]
        else
          [_dex_resolve_subject([]), nil]
        end
      end

      def _dex_split_class_and_symbols(args)
        if args.first.is_a?(Class) && args.first < Dex::Operation
          [args[0..0], args[1..]]
        else
          [[], args]
        end
      end

      def _dex_split_class_and_hash(args)
        hash = args.pop
        klass_args = args.select { |a| a.is_a?(Class) && a < Dex::Operation }
        [klass_args, hash]
      end

      def _dex_ensure_active_job_test_helper!
        return if respond_to?(:assert_enqueued_with)

        raise "assert_enqueues_operation requires ActiveJob::TestHelper. " \
              "Include it in your test class: `include ActiveJob::TestHelper`"
      end
    end
  end
end
