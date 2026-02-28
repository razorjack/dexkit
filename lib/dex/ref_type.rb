# frozen_string_literal: true

module Dex
  class RefType
    include Literal::Type

    attr_reader :model_class, :lock

    def initialize(model_class, lock: false)
      @model_class = model_class
      @lock = lock
    end

    def ===(value)
      value.is_a?(@model_class)
    end

    def >=(other, context: nil)
      other.is_a?(RefType) && other.model_class <= @model_class
    end

    def coerce(value)
      return value if value.is_a?(@model_class)
      return value if value.nil?

      scope = @lock ? @model_class.lock : @model_class
      scope.find(value)
    end

    def inspect
      @lock ? "_Ref(#{@model_class}, lock: true)" : "_Ref(#{@model_class})"
    end
  end
end
