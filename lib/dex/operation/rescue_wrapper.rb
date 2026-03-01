# frozen_string_literal: true

module Dex
  module RescueWrapper
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def rescue_from(*exception_classes, as:, message: nil)
        raise ArgumentError, "rescue_from requires at least one exception class" if exception_classes.empty?

        invalid = exception_classes.reject { |k| k.is_a?(Module) && k <= Exception }
        if invalid.any?
          raise ArgumentError,
            "rescue_from expects Exception subclasses, got: #{invalid.map(&:inspect).join(", ")}"
        end

        raise ArgumentError, "rescue_from :as must be a Symbol, got: #{as.inspect}" unless as.is_a?(Symbol)

        exception_classes.each do |klass|
          _rescue_own << { exception_class: klass, code: as, message: message }
        end
      end

      def _rescue_handlers
        parent = superclass.respond_to?(:_rescue_handlers) ? superclass._rescue_handlers : []
        parent + _rescue_own
      end

      private

      def _rescue_own
        @_rescue_handlers ||= []
      end
    end

    def _rescue_wrap
      yield
    rescue Dex::Error
      raise
    rescue => e
      handler = _rescue_find_handler(e)
      raise unless handler

      _rescue_convert!(e, handler)
    end

    private

    def _rescue_find_handler(exception)
      self.class._rescue_handlers.reverse_each do |handler|
        return handler if exception.is_a?(handler[:exception_class])
      end
      nil
    end

    def _rescue_convert!(exception, handler)
      msg = handler[:message] || exception.message
      raise Dex::Error.new(handler[:code], msg, details: { original: exception })
    end
  end
end
