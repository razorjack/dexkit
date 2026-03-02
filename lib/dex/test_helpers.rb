# frozen_string_literal: true

require_relative "test_log"

module Dex
  module TestWrapper
    @_installed = false

    class << self
      def install!
        return if @_installed

        Dex::Operation.prepend(self)
        @_installed = true
      end

      def installed?
        @_installed
      end

      # Stub registry

      def stubs
        @_stubs ||= {}
      end

      def find_stub(klass)
        stubs[klass]
      end

      def register_stub(klass, **options)
        stubs[klass] = options
      end

      def clear_stub(klass)
        stubs.delete(klass)
      end

      def clear_all_stubs!
        stubs.clear
      end
    end

    def call
      stub = Dex::TestWrapper.find_stub(self.class)
      return _test_apply_stub(stub) if stub

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = nil
      err = nil

      begin
        result = super
      rescue Exception => e # rubocop:disable Lint/RescueException
        err = e
        raise
      ensure
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        _test_record_to_log(result, err, duration)
      end

      result
    end

    private

    def _test_apply_stub(stub)
      if stub[:error]
        err_opts = stub[:error]
        case err_opts
        when Symbol
          raise Dex::Error.new(err_opts)
        when Hash
          raise Dex::Error.new(err_opts[:code], err_opts[:message], details: err_opts[:details])
        end
      else
        stub[:returns]
      end
    end

    def _test_safe_params
      respond_to?(:to_h) ? to_h : {}
    rescue
      {}
    end

    def _test_record_to_log(result, err, duration)
      safe_result = if err
        dex_err = if err.is_a?(Dex::Error)
          err
        else
          Dex::Error.new(:exception, err.message, details: { exception_class: err.class.name })
        end
        Dex::Operation::Err.new(dex_err)
      else
        Dex::Operation::Ok.new(result)
      end

      entry = Dex::TestLog::Entry.new(
        type: "Operation",
        name: self.class.name || self.class.to_s,
        operation_class: self.class,
        params: _test_safe_params,
        result: safe_result,
        duration: duration,
        caller_location: caller_locations(4, 1)&.first
      )
      Dex::TestLog.record(entry)
    end
  end

  module TestHelpers
    extend Dex::Concern

    def self.included(base)
      Dex::TestWrapper.install!
      super
    end

    def setup
      super
      Dex::TestLog.clear!
      Dex::TestWrapper.clear_all_stubs!
    end

    module ClassMethods
      def testing(klass)
        @_dex_test_subject = klass
      end

      def _dex_test_subject
        return @_dex_test_subject if defined?(@_dex_test_subject) && @_dex_test_subject

        superclass._dex_test_subject if superclass.respond_to?(:_dex_test_subject)
      end
    end

    private

    def _dex_test_subject
      self.class._dex_test_subject
    end
  end
end

require_relative "test_helpers/execution"
require_relative "test_helpers/assertions"
require_relative "test_helpers/stubbing"
