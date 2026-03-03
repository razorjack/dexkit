# frozen_string_literal: true

require "active_model"

require_relative "form/nesting"

module Dex
  class Form
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveModel::Validations::Callbacks

    if defined?(ActiveModel::Attributes::Normalization)
      include ActiveModel::Attributes::Normalization
    end

    include Nesting

    class ValidationError < StandardError
      attr_reader :form

      def initialize(form)
        @form = form
        super("Validation failed: #{form.errors.full_messages.join(", ")}")
      end
    end

    class << self
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
        subclass.instance_variable_set(:@_nested_ones, _nested_ones.dup)
        subclass.instance_variable_set(:@_nested_manys, _nested_manys.dup)
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
      super_result = super
      nested_result = _validate_nested(context)
      super_result && nested_result
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

    private

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
