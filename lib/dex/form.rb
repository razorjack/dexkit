# frozen_string_literal: true

require "active_model"

require_relative "form/nesting"
require_relative "form/context"

module Dex
  class Form
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveModel::Validations::Callbacks

    if defined?(ActiveModel::Attributes::Normalization)
      include ActiveModel::Attributes::Normalization
    end

    include Nesting
    include Context
    include Match

    extend Registry

    FIELD_DEFAULT_UNSET = Object.new.freeze

    FieldDef = Data.define(:name, :type, :desc, :required, :default) do
      def default? = !default.equal?(Dex::Form::FIELD_DEFAULT_UNSET)
    end

    class ValidationError < StandardError
      attr_reader :form

      def initialize(form)
        @form = form
        super("Validation failed: #{form.errors.full_messages.join(", ")}")
      end
    end

    class << self
      def _field_registry
        @_field_registry ||= {}
      end

      def _required_fields
        _field_registry.each_with_object([]) do |(name, f), list|
          list << name if f.required
        end
      end

      def field(name, type, desc: nil, default: FIELD_DEFAULT_UNSET, **options)
        raise ArgumentError, "field name must be a Symbol, got #{name.inspect}" unless name.is_a?(Symbol)
        raise ArgumentError, "field type must be a Symbol, got #{type.inspect}" unless type.is_a?(Symbol)
        raise ArgumentError, "desc must be a String, got #{desc.inspect}" if desc && !desc.is_a?(String)

        am_options = options.dup
        am_options[:default] = default unless default.equal?(FIELD_DEFAULT_UNSET)
        attribute name, type, **am_options
        _field_registry[name] = FieldDef.new(name: name, type: type, desc: desc, required: true, default: default)
      end

      def field?(name, type, desc: nil, default: FIELD_DEFAULT_UNSET, **options)
        raise ArgumentError, "field name must be a Symbol, got #{name.inspect}" unless name.is_a?(Symbol)
        raise ArgumentError, "field type must be a Symbol, got #{type.inspect}" unless type.is_a?(Symbol)
        raise ArgumentError, "desc must be a String, got #{desc.inspect}" if desc && !desc.is_a?(String)

        actual_default = default.equal?(FIELD_DEFAULT_UNSET) ? nil : default
        attribute name, type, default: actual_default, **options
        _field_registry[name] = FieldDef.new(name: name, type: type, desc: desc, required: false, default: default)
      end

      def model(klass = nil)
        if klass
          raise ArgumentError, "model must be a Class, got #{klass.inspect}" unless klass.is_a?(Class)
          @_model_class = klass
        end
        _model_class
      end

      def _model_class
        return @_model_class if defined?(@_model_class)
        superclass._model_class if superclass.respond_to?(:_model_class)
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@_field_registry, _field_registry.dup)
        subclass.instance_variable_set(:@_nested_ones, _nested_ones.dup)
        subclass.instance_variable_set(:@_nested_manys, _nested_manys.dup)
      end

      def _dex_nested_form?
        !!instance_variable_get(:@_dex_nested_form)
      end

      # Export

      def to_h
        Export.build_hash(self)
      end

      def to_json_schema
        Export.build_json_schema(self)
      end

      def export(format: :hash)
        unless %i[hash json_schema].include?(format)
          raise ArgumentError, "unknown format: #{format.inspect}. Known: :hash, :json_schema"
        end

        sorted = registry.reject { |klass| klass._dex_nested_form? }.sort_by(&:name)
        sorted.map do |klass|
          case format
          when :hash then klass.to_h
          when :json_schema then klass.to_json_schema
          end
        end
      end
    end

    silence_redefinition_of_method :model_name
    def self.model_name
      if _model_class
        _model_class.model_name
      elsif name && !name.start_with?("#")
        super
      else
        @_model_name ||= ActiveModel::Name.new(self, nil, name&.split("::")&.last || "Form")
      end
    end

    attr_reader :record

    def initialize(attributes = {})
      # Accept ActionController::Parameters without requiring .permit — the form's
      # attribute declarations are the whitelist. Only declared attributes and nested
      # setters are assignable; everything else is silently dropped.
      attributes = attributes.to_unsafe_h if attributes.respond_to?(:to_unsafe_h)
      attrs = (attributes || {}).transform_keys(&:to_s)

      # Context injection — fill ambient values for unmapped keys
      mappings = self.class.context_mappings
      unless mappings.empty?
        ambient = Dex.context
        mappings.each do |attr_name, context_key|
          str_name = attr_name.to_s
          next if attrs.key?(str_name)
          attrs[str_name] = ambient[context_key] if ambient.key?(context_key)
        end
      end

      record = attrs.delete("record")
      @record = record if record.nil? || record.respond_to?(:persisted?)
      provided_keys = attrs.keys
      nested_attrs = _extract_nested_attributes(attrs)
      super(attrs.slice(*self.class.attribute_names))
      _apply_nested_attributes(nested_attrs)
      _initialize_nested_defaults(provided_keys)
    end

    def with_record(record)
      raise ArgumentError, "record must respond to #persisted?, got #{record.inspect}" unless record.respond_to?(:persisted?)

      @record = record
      self
    end

    def persisted?
      record&.persisted? || false
    end

    def to_key
      record&.to_key
    end

    def to_param
      record&.to_param
    end

    def valid?(context = nil)
      super
      _fix_boolean_presence_errors
      nested_valid = _validate_nested(context)
      errors.empty? && nested_valid
    end

    def to_h
      result = {}
      self.class.attribute_names.each do |name|
        result[name.to_sym] = public_send(name)
      end
      _nested_to_h(result)
      result
    end

    alias_method :to_hash, :to_h

    validate :_validate_required_fields

    private

    def _validate_required_fields
      explicit = self.class.validators
        .select { |v| v.is_a?(ActiveModel::Validations::PresenceValidator) }
        .reject { |v| v.options.key?(:on) || v.options.key?(:if) || v.options.key?(:unless) }
        .flat_map(&:attributes).map(&:to_sym).to_set

      self.class._required_fields.each do |name|
        next if explicit.include?(name)
        field_def = self.class._field_registry[name]
        value = public_send(name)
        blank = (field_def.type == :boolean) ? value.nil? : value.blank?
        errors.add(name, :blank) if blank
      end
    end

    def _fix_boolean_presence_errors
      explicit = self.class.validators
        .select { |v| v.is_a?(ActiveModel::Validations::PresenceValidator) }
        .reject { |v| v.options.key?(:on) || v.options.key?(:if) || v.options.key?(:unless) }
        .flat_map(&:attributes).map(&:to_sym)

      explicit.each do |name|
        field_def = self.class._field_registry[name]
        next unless field_def&.type == :boolean
        next if public_send(name).nil?

        errors.delete(name, :blank)
      end
    end

    def _extract_nested_attributes(attrs)
      nested_keys = self.class._nested_ones.keys.map(&:to_s) +
        self.class._nested_manys.keys.map(&:to_s)

      extracted = {}
      nested_keys.each do |key|
        attr_key = "#{key}_attributes"
        if attrs.key?(attr_key)
          extracted[attr_key] = attrs.delete(attr_key)
          attrs.delete(key)
        elsif attrs.key?(key)
          extracted[key] = attrs.delete(key)
        end
      end
      extracted
    end

    def _apply_nested_attributes(nested_attrs)
      nested_attrs.each do |key, value|
        next if value.nil?
        send(:"#{key}=", value)
      end
    end
  end
end

require_relative "form/uniqueness_validator"
require_relative "form/export"
