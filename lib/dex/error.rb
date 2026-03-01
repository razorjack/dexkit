# frozen_string_literal: true

module Dex
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message = nil, details: nil)
      @code = code
      @details = details
      super(message || code.to_s)
    end

    def deconstruct_keys(keys)
      { code: @code, message: message, details: @details }
    end
  end
end
