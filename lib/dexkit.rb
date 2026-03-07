# frozen_string_literal: true

require "zeitwerk"

require "literal"
require "time"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/dex")
loader.setup

require_relative "dex/version"
require_relative "dex/concern"
require_relative "dex/ref_type"
require_relative "dex/type_coercion"
require_relative "dex/props_setup"
require_relative "dex/context_setup"
require_relative "dex/error"
require_relative "dex/settings"
require_relative "dex/pipeline"
require_relative "dex/executable"
require_relative "dex/operation"
require_relative "dex/event"
require_relative "dex/form"
require_relative "dex/query"

module Dex
  class Configuration
    attr_accessor :record_class, :transaction_adapter, :event_store, :event_context, :restore_event_context

    def initialize
      @record_class = nil
      @transaction_adapter = nil
      @event_store = nil
      @event_context = nil
      @restore_event_context = nil
    end
  end

  class << self
    def warn(message)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn("[Dex] #{message}")
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def record_class
      configuration.record_class
    end

    def record_backend
      return @record_backend if defined?(@record_backend)
      @record_backend = Operation::RecordBackend.for(record_class)
    end

    def reset_record_backend!
      remove_instance_variable(:@record_backend) if defined?(@record_backend)
    end

    def transaction_adapter
      configuration.transaction_adapter
    end

    def transaction_adapter=(adapter)
      configuration.transaction_adapter = adapter
    end

    CONTEXT_KEY = :_dex_context
    EMPTY_CONTEXT = {}.freeze

    def context
      Fiber[CONTEXT_KEY] || EMPTY_CONTEXT
    end

    def with_context(**values)
      previous = Fiber[CONTEXT_KEY]
      Fiber[CONTEXT_KEY] = (previous || {}).merge(values)
      yield
    ensure
      Fiber[CONTEXT_KEY] = previous
    end
  end
end
