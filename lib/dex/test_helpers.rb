# frozen_string_literal: true

require_relative "operation/test_helpers"
require_relative "event/test_helpers"

module Dex
  module TestHelpers
    def self.included(base)
      base.include(Dex::Operation::TestHelpers)
      base.include(Dex::Event::TestHelpers)
    end
  end
end
