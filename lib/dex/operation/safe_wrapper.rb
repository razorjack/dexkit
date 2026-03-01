# frozen_string_literal: true

module Dex
  module SafeWrapper
    def safe
      Operation::SafeProxy.new(self)
    end
  end
end
