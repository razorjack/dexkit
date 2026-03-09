# frozen_string_literal: true

module Dex
  module TypeCoercion
    extend Dex::Concern

    module ClassMethods
      def _serialized_coercions
        @_serialized_coercions ||= {
          Time => ->(v) { v.is_a?(String) ? Time.parse(v) : v },
          Symbol => ->(v) { v.is_a?(String) ? v.to_sym : v }
        }.tap do |h|
          h[Date] = ->(v) { v.is_a?(String) ? Date.parse(v) : v } if defined?(Date)
          h[DateTime] = ->(v) { v.is_a?(String) ? DateTime.parse(v) : v } if defined?(DateTime)
          h[BigDecimal] = ->(v) { v.is_a?(String) ? BigDecimal(v) : v } if defined?(BigDecimal)
        end.freeze
      end

      private

      def _find_ref_type(type)
        return type if type.is_a?(Dex::RefType)

        if type.respond_to?(:type)
          inner = type.type
          return inner if inner.is_a?(Dex::RefType)
        end
        nil
      end

      def _resolve_base_class(type)
        return type.model_class if type.is_a?(Dex::RefType)
        return _resolve_base_class(type.type) if type.respond_to?(:type)

        type if type.is_a?(Class)
      end

      def _coerce_value(type, value)
        return value unless value

        if type.is_a?(Literal::Types::ArrayType)
          return value.map { |v| _coerce_value(type.type, v) } if value.is_a?(Array)

          return value
        end

        return _coerce_value(type.type, value) if type.is_a?(Literal::Types::NilableType)

        ref = _find_ref_type(type)
        return ref.coerce(value) if ref

        base = _resolve_base_class(type)
        coercion = _serialized_coercions[base]
        coercion ? coercion.call(value) : value
      end

      def _serialize_value(type, value)
        return value unless value

        if type.is_a?(Literal::Types::ArrayType) && value.is_a?(Array)
          return value.map { |v| _serialize_value(type.type, v) }
        end

        return _serialize_value(type.type, value) if type.is_a?(Literal::Types::NilableType)

        ref = _find_ref_type(type)
        if ref
          serialized_id = value.id
          return serialized_id.respond_to?(:as_json) ? serialized_id.as_json : serialized_id
        end

        value.respond_to?(:as_json) ? value.as_json : value
      end

      def _coerce_serialized_hash(hash)
        return hash.transform_keys(&:to_sym) unless respond_to?(:literal_properties)

        result = {}
        literal_properties.each do |prop|
          name = prop.name
          raw = hash.key?(name) ? hash[name] : hash[name.to_s]
          result[name] = _coerce_value(prop.type, raw)
        end
        result
      end
    end

    def _props_as_json
      return {} unless self.class.respond_to?(:literal_properties)

      result = {}
      self.class.literal_properties.each do |prop|
        value = public_send(prop.name)
        result[prop.name.to_s] = self.class.send(:_serialize_value, prop.type, value)
      end
      result
    end
  end
end
