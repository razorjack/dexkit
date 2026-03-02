# frozen_string_literal: true

module Dex
  # Shared prop DSL for Operation and Event.
  #
  # Wraps Literal::Properties' prop/prop? with three Dex-specific behaviors:
  #   1. Reserved name validation — each class defines RESERVED_PROP_NAMES
  #   2. reader: :public by default (Literal defaults to private)
  #   3. Automatic RefType coercion — _Ref(Model) props auto-coerce IDs to records
  module PropsSetup
    extend Dex::Concern

    def self.included(base)
      base.extend(Literal::Properties)
      base.extend(Literal::Types)
      super
    end

    module ClassMethods
      def prop(name, type, kind = :keyword, **options, &block)
        if const_defined?(:RESERVED_PROP_NAMES) && self::RESERVED_PROP_NAMES.include?(name)
          raise ArgumentError, "Property :#{name} is reserved."
        end
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
    end
  end
end
