# frozen_string_literal: true

module Dex
  module AsyncWrapper
    ASYNC_KNOWN_OPTIONS = %i[queue in at].freeze

    module ClassMethods
      def async(**options)
        unknown = options.keys - AsyncWrapper::ASYNC_KNOWN_OPTIONS
        if unknown.any?
          raise ArgumentError,
            "unknown async option(s): #{unknown.map(&:inspect).join(", ")}. " \
            "Known: #{AsyncWrapper::ASYNC_KNOWN_OPTIONS.map(&:inspect).join(", ")}"
        end

        set(:async, **options)
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def async(**options)
      unknown = options.keys - AsyncWrapper::ASYNC_KNOWN_OPTIONS
      if unknown.any?
        raise ArgumentError,
          "unknown async option(s): #{unknown.map(&:inspect).join(", ")}. " \
          "Known: #{AsyncWrapper::ASYNC_KNOWN_OPTIONS.map(&:inspect).join(", ")}"
      end

      Operation::AsyncProxy.new(self, **options)
    end
  end
end
