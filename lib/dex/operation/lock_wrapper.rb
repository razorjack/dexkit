# frozen_string_literal: true

module Dex
  module LockWrapper
    extend Dex::Concern

    module ClassMethods
      def advisory_lock(key = nil, **options, &block)
        validate_options!(options, %i[timeout], :advisory_lock)

        lock_key = block || key

        unless lock_key.nil? || lock_key.is_a?(String) || lock_key.is_a?(Symbol) || lock_key.is_a?(Proc)
          raise ArgumentError, "advisory_lock key must be a String, Symbol, or Proc, got: #{lock_key.class}"
        end

        if options.key?(:timeout) && !options[:timeout].is_a?(Numeric)
          raise ArgumentError, "advisory_lock :timeout must be Numeric, got: #{options[:timeout].inspect}"
        end

        set(:advisory_lock, enabled: true, key: lock_key, **options)
      end
    end

    def _lock_wrap
      _lock_enabled? ? _lock_execute { yield } : yield
    end

    private

    def _lock_enabled?
      self.class.settings_for(:advisory_lock).fetch(:enabled, false)
    end

    def _lock_key
      key = self.class.settings_for(:advisory_lock)[:key]
      case key
      when String then key
      when Symbol then send(key)
      when Proc then instance_exec(&key)
      when nil then self.class.name || raise(ArgumentError, "Anonymous classes must provide an explicit lock key")
      else raise ArgumentError, "Unsupported advisory_lock key type: #{key.class}"
      end
    end

    def _lock_options
      opts = {}
      timeout = self.class.settings_for(:advisory_lock)[:timeout]
      opts[:timeout_seconds] = timeout if timeout
      opts
    end

    def _lock_execute(&block)
      _lock_ensure_loaded!
      key = _lock_key
      ActiveRecord::Base.with_advisory_lock!(key, **_lock_options, &block)
    rescue WithAdvisoryLock::FailedToAcquireLock
      raise Dex::Error.new(:lock_timeout, "Could not acquire advisory lock: #{key}")
    end

    def _lock_ensure_loaded!
      return if ActiveRecord::Base.respond_to?(:with_advisory_lock!)

      raise LoadError,
        "with_advisory_lock gem is required for advisory locking. Add 'with_advisory_lock' to your Gemfile."
    end
  end
end
