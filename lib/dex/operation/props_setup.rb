# frozen_string_literal: true

require "set"

module Dex
  module PropsSetup
    def self.included(base)
      base.extend(Literal::Properties)
      base.extend(Literal::Types)
      base.extend(ClassMethods)
    end

    module ClassMethods
      RESERVED_PROP_NAMES = %i[call perform async safe initialize].to_set.freeze

      def prop(name, type, kind = :keyword, **options, &block)
        _props_validate_name!(name)
        options[:reader] = :public unless options.key?(:reader)
        if type.is_a?(Dex::RefType) && !block
          ref = type
          block = ->(v) { ref.coerce(v) }
        end
        super(name, type, kind, **options, &block)
      end

      def prop?(name, type, kind = :keyword, **options, &block)
        options[:reader] = :public unless options.key?(:reader)
        options[:default] = nil unless options.key?(:default)
        if type.is_a?(Dex::RefType) && !block
          ref = type
          block = ->(v) { v.nil? ? v : ref.coerce(v) }
        end
        prop(name, _Nilable(type), kind, **options, &block)
      end

      def _Ref(model_class, lock: false) # rubocop:disable Naming/MethodName
        Dex::RefType.new(model_class, lock: lock)
      end

      private

      def _props_validate_name!(name)
        return unless RESERVED_PROP_NAMES.include?(name)

        raise ArgumentError,
          "Property :#{name} conflicts with core Operation methods."
      end
    end
  end
end
