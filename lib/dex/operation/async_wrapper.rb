# frozen_string_literal: true

module Dex
  module AsyncWrapper
    module ClassMethods
      def async(**options)
        validate_options!(options, %i[queue in at], :async)
        set(:async, **options)
      end
    end

    extend Dex::Concern

    def async(**options)
      self.class.validate_options!(options, %i[queue in at], :async)
      Operation::AsyncProxy.new(self, **options)
    end
  end
end
