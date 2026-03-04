# frozen_string_literal: true

require "active_model"

require_relative "query/backend"
require_relative "query/filtering"
require_relative "query/sorting"

module Dex
  class Query
    RESERVED_PROP_NAMES = %i[scope sort resolve call from_params to_params param_key].to_set.freeze

    include PropsSetup
    include Filtering
    include Sorting

    extend ActiveModel::Naming
    include ActiveModel::Conversion

    class << self
      def scope(&block)
        raise ArgumentError, "scope requires a block." unless block

        @_scope_block = block
      end

      def _scope_block
        return @_scope_block if defined?(@_scope_block)

        superclass._scope_block if superclass.respond_to?(:_scope_block)
      end

      def new(scope: nil, sort: nil, **kwargs)
        instance = super(**kwargs)
        instance.instance_variable_set(:@_injected_scope, scope)
        sort_str = sort&.to_s
        sort_str = nil if sort_str&.empty?
        instance.instance_variable_set(:@_sort_value, sort_str)
        instance
      end

      def call(scope: nil, sort: nil, **kwargs)
        new(scope: scope, sort: sort, **kwargs).resolve
      end

      def count(...)
        call(...).count
      end

      def exists?(...)
        call(...).exists?
      end

      def any?(...)
        call(...).any?
      end

      def param_key(key = nil)
        if key
          str = key.to_s
          raise ArgumentError, "param_key must not be blank." if str.empty?

          @_param_key = str
          @_model_name = nil
        end
        defined?(@_param_key) ? @_param_key : nil
      end

      silence_redefinition_of_method :model_name
      def model_name
        return @_model_name if @_model_name

        pk = param_key
        @_model_name = if pk
          ActiveModel::Name.new(self, nil, pk.to_s.camelize).tap do |mn|
            mn.define_singleton_method(:param_key) { pk }
          end
        elsif name && !name.start_with?("#")
          super
        else
          ActiveModel::Name.new(self, nil, "Query")
        end
      end

      def _prop_optional?(name)
        return false unless respond_to?(:literal_properties)

        prop = literal_properties.find { |p| p.name == name }
        prop&.type.is_a?(Literal::Types::NilableType) || false
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@_filter_registry, _filter_registry.dup)
        subclass.instance_variable_set(:@_sort_registry, _sort_registry.dup)
        subclass.instance_variable_set(:@_sort_default, _sort_default) if _sort_default
      end

      def from_params(params, scope: nil, **overrides)
        pk = model_name.param_key
        nested = _extract_nested_params(params, pk)

        sort_value = overrides.delete(:sort)&.to_s
        unless sort_value && !sort_value.empty?
          sort_value = nested.delete(:sort)&.to_s
          sort_value = nil if sort_value && sort_value.empty?

          # Validate sort — drop invalid to fall back to default
          if sort_value
            bare = sort_value.delete_prefix("-").to_sym
            sort_def = _sort_registry[bare]
            sort_value = nil if sort_def.nil? || (sort_value.start_with?("-") && sort_def.custom)
          end
        end

        kwargs = {}

        literal_properties.each do |prop|
          pname = prop.name
          next if overrides.key?(pname)
          next if _ref_type?(prop.type)

          raw = nested[pname]

          if raw.nil? || (raw.is_a?(String) && raw.empty? && _prop_optional?(pname))
            kwargs[pname] = nil if _prop_optional?(pname)
            next
          end

          kwargs[pname] = _coerce_param(prop.type, raw)
        end

        kwargs.merge!(overrides)
        kwargs[:sort] = sort_value if sort_value
        kwargs[:scope] = scope if scope

        new(**kwargs)
      end

      private

      def _extract_nested_params(params, pk)
        hash = if params.respond_to?(:to_unsafe_h)
          params.to_unsafe_h
        elsif params.is_a?(Hash)
          params
        else
          {}
        end

        nested = hash[pk] || hash[pk.to_sym] || hash
        nested = nested.to_unsafe_h if nested.respond_to?(:to_unsafe_h)
        return {} unless nested.is_a?(Hash)

        nested.transform_keys(&:to_sym)
      end

      def _ref_type?(type)
        return true if type.is_a?(Dex::RefType)
        return _ref_type?(type.type) if type.respond_to?(:type)

        false
      end

      def _coerce_param(type, raw)
        inner = type.is_a?(Literal::Types::NilableType) ? type.type : type

        if inner.is_a?(Literal::Types::ArrayType)
          values = Array(raw)
          values = values.reject { |v| v.is_a?(String) && v.empty? }
          return values.map { |v| _coerce_single(inner.type, v) }.compact
        end

        _coerce_single(inner, raw)
      end

      def _coerce_single(type, value)
        return value unless value.is_a?(String)

        base = _resolve_coercion_class(type)
        return value unless base

        case base.name
        when "Integer"
          Integer(value, 10)
        when "Float"
          Float(value)
        when "Date"
          Date.parse(value)
        when "Time"
          Time.parse(value)
        when "DateTime"
          DateTime.parse(value)
        when "BigDecimal"
          BigDecimal(value)
        else
          value
        end
      rescue ArgumentError, TypeError
        nil
      end

      def _resolve_coercion_class(type)
        return type if type.is_a?(Class)
        return _resolve_coercion_class(type.type) if type.respond_to?(:type)

        nil
      end
    end

    def resolve
      base = _evaluate_scope
      base = _merge_injected_scope(base)
      base = _apply_filters(base)
      _apply_sort(base)
    end

    def sort
      _current_sort
    end

    def to_params
      result = {}

      self.class.literal_properties.each do |prop|
        value = public_send(prop.name)
        result[prop.name] = value unless value.nil?
      end

      s = _current_sort
      result[:sort] = s if s

      result
    end

    def persisted?
      false
    end

    private

    def _current_sort
      @_sort_value || self.class._sort_default
    end

    def _evaluate_scope
      block = self.class._scope_block
      raise ArgumentError, "No scope defined. Use `scope { Model.all }` in your Query class." unless block

      instance_exec(&block)
    end

    def _merge_injected_scope(base)
      return base unless @_injected_scope

      unless base.respond_to?(:klass)
        raise ArgumentError, "Scope block must return a queryable scope (ActiveRecord relation or Mongoid criteria), got #{base.class}."
      end

      unless @_injected_scope.respond_to?(:klass)
        raise ArgumentError, "Injected scope must be a queryable scope (ActiveRecord relation or Mongoid criteria), got #{@_injected_scope.class}."
      end

      unless base.klass == @_injected_scope.klass
        raise ArgumentError, "Scope model mismatch: expected #{base.klass}, got #{@_injected_scope.klass}."
      end

      base.merge(@_injected_scope)
    end
  end
end
