# frozen_string_literal: true

module Dex
  class Form
    module Nesting
      extend Dex::Concern

      module ClassMethods
        def _nested_ones
          @_nested_ones ||= {}
        end

        def _nested_manys
          @_nested_manys ||= {}
        end

        def nested_one(name, class_name: nil, &block)
          raise ArgumentError, "nested_one requires a block" unless block

          name = name.to_sym
          nested_class = _build_nested_class(name, class_name, &block)
          _nested_ones[name] = nested_class

          attr_reader name

          define_method(:"#{name}=") do |value|
            coerced = _coerce_nested_one(name, value)
            instance_variable_set(:"@#{name}", coerced)
          end

          define_method(:"build_#{name}") do |attrs = {}|
            instance = self.class._nested_ones[name].new(attrs)
            send(:"#{name}=", instance)
            instance
          end

          define_method(:"#{name}_attributes=") do |attrs|
            send(:"#{name}=", attrs)
          end
        end

        def nested_many(name, class_name: nil, &block)
          raise ArgumentError, "nested_many requires a block" unless block

          name = name.to_sym
          nested_class = _build_nested_class(name, class_name, &block)
          _nested_manys[name] = nested_class

          attr_reader name

          define_method(:"#{name}=") do |value|
            coerced = _coerce_nested_many(name, value)
            instance_variable_set(:"@#{name}", coerced)
          end

          define_method(:"build_#{name.to_s.singularize}") do |attrs = {}|
            instance = self.class._nested_manys[name].new(attrs)
            items = send(name) || []
            items << instance
            instance_variable_set(:"@#{name}", items)
            instance
          end

          define_method(:"#{name}_attributes=") do |attrs|
            send(:"#{name}=", attrs)
          end
        end

        private

        def _build_nested_class(name, class_name, &block)
          klass = Class.new(Dex::Form, &block)
          klass.instance_variable_set(:@_dex_nested_form, true)
          Dex::Form.deregister(klass)
          const_name = class_name || name.to_s.singularize.camelize
          const_set(const_name, klass)
          klass
        end
      end

      private

      def _coerce_nested_one(name, value)
        klass = self.class._nested_ones[name]
        value = _unwrap_hash_like(value)
        case value
        when Hash
          return nil if _marked_for_destroy?(value)
          klass.new(value.except("_destroy", :_destroy))
        when klass then value
        when nil then value
        else raise ArgumentError, "#{name} must be a Hash or #{klass}, got #{value.class}"
        end
      end

      def _coerce_nested_many(name, value)
        klass = self.class._nested_manys[name]
        value = _unwrap_hash_like(value)
        items = case value
        when Array then value
        when Hash then _normalize_nested_hash(value)
        else raise ArgumentError, "#{name} must be an Array or Hash, got #{value.class}"
        end

        items.filter_map do |item|
          item = _unwrap_hash_like(item)
          case item
          when Hash
            next nil if _marked_for_destroy?(item)
            klass.new(item.except("_destroy", :_destroy))
          when klass then item
          else raise ArgumentError, "each #{name} item must be a Hash or #{klass}"
          end
        end
      end

      def _unwrap_hash_like(value)
        return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
        return value if value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(Dex::Form) || value.nil?

        value.respond_to?(:to_h) ? value.to_h : value
      end

      def _normalize_nested_hash(hash)
        hash.sort_by { |k, _| k.to_s.to_i }.map(&:last)
      end

      def _marked_for_destroy?(attrs)
        destroy_val = attrs["_destroy"] || attrs[:_destroy]
        ActiveModel::Type::Boolean.new.cast(destroy_val)
      end

      def _initialize_nested_defaults(provided_keys)
        self.class._nested_ones.each_key do |name|
          key = name.to_s
          next if provided_keys.include?(key) || provided_keys.include?("#{key}_attributes")

          send(:"#{name}=", {})
        end

        self.class._nested_manys.each_key do |name|
          next if instance_variable_get(:"@#{name}")

          instance_variable_set(:"@#{name}", [])
        end
      end

      def _validate_nested(context)
        valid = true

        self.class._nested_ones.each_key do |name|
          nested = send(name)
          next unless nested

          unless nested.valid?(context)
            nested.errors.each do |error|
              errors.add(:"#{name}.#{error.attribute}", error.message)
            end
            valid = false
          end
        end

        self.class._nested_manys.each_key do |name|
          items = send(name) || []
          items.each_with_index do |item, index|
            next if item.valid?(context)

            item.errors.each do |error|
              errors.add(:"#{name}[#{index}].#{error.attribute}", error.message)
            end
            valid = false
          end
        end

        valid
      end

      def _nested_to_h(result)
        self.class._nested_ones.each_key do |name|
          nested = send(name)
          result[name] = nested&.to_h
        end

        self.class._nested_manys.each_key do |name|
          items = send(name) || []
          result[name] = items.map(&:to_h)
        end
      end
    end
  end
end
