# frozen_string_literal: true

require "zeitwerk"

require "dry/types"
require "dry/struct"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/dex")
loader.setup

require_relative "dex/version"
require_relative "dex/parameters"
require_relative "dex/operation"

module Dex
  class Configuration
    attr_accessor :record_class

    def initialize
      @record_class = nil
    end
  end

  class << self
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
  end
end
