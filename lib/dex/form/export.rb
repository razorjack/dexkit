# frozen_string_literal: true

module Dex
  class Form
    module Export
      module_function

      TYPE_MAP = {
        string: { type: "string" },
        integer: { type: "integer" },
        float: { type: "number" },
        decimal: { type: "number" },
        boolean: { type: "boolean" },
        date: { type: "string", format: "date" },
        datetime: { type: "string", format: "date-time" },
        time: { type: "string", format: "time" }
      }.freeze

      def build_hash(source)
        h = _serialize_form_definition(source)
        h[:name] = source.name if source.name
        desc = source.description
        h[:description] = desc if desc
        h
      end

      def build_json_schema(source) # rubocop:disable Metrics/MethodLength
        properties = {}
        required = []

        source._field_registry.each do |name, field_def|
          schema = _field_to_schema(field_def)
          properties[name.to_s] = schema
          required << name.to_s if field_def.required
        end

        _add_nested_properties(source, properties, required)

        result = { "$schema": "https://json-schema.org/draft/2020-12/schema", type: "object" }
        result[:title] = source.name if source.name
        desc = source.description
        result[:description] = desc if desc
        result[:properties] = properties unless properties.empty?
        result[:required] = required unless required.empty?
        result[:additionalProperties] = false
        result
      end

      def _serialize_fields(source)
        source._field_registry.each_with_object({}) do |(name, field_def), hash|
          entry = { type: field_def.type, required: field_def.required }
          entry[:desc] = field_def.desc if field_def.desc
          entry[:default] = field_def.default if field_def.default?
          hash[name] = entry
        end
      end

      def _serialize_form_definition(source)
        h = { fields: _serialize_fields(source) }
        nested = _serialize_nested(source)
        h[:nested] = nested unless nested.empty?
        h
      end

      def _serialize_nested(source)
        nested = {}
        source._nested_ones.each do |name, klass|
          nested[name] = { type: :one }.merge(_serialize_form_definition(klass))
        end
        source._nested_manys.each do |name, klass|
          nested[name] = { type: :many }.merge(_serialize_form_definition(klass))
        end
        nested
      end

      def _field_to_schema(field_def)
        schema = TYPE_MAP[field_def.type]&.dup || {}
        schema[:description] = field_def.desc if field_def.desc
        schema[:default] = _coerce_default(field_def) if field_def.default?
        schema
      end

      def _coerce_default(field_def)
        val = field_def.default
        case field_def.type
        when :integer then val.is_a?(Integer) ? val : val.to_i
        when :float, :decimal then val.is_a?(Float) ? val : val.to_f
        when :boolean then !!val
        when :string, :date, :datetime, :time then val.to_s
        else val
        end
      end

      def _nested_json_schema(klass)
        properties = {}
        required = []

        klass._field_registry.each do |name, field_def|
          schema = _field_to_schema(field_def)
          properties[name.to_s] = schema
          required << name.to_s if field_def.required
        end

        _add_nested_properties(klass, properties, required)

        result = { type: "object" }
        result[:properties] = properties unless properties.empty?
        result[:required] = required unless required.empty?
        result[:additionalProperties] = false
        result
      end

      def _add_nested_properties(source, properties, required)
        source._nested_ones.each do |name, klass|
          properties[name.to_s] = _nested_json_schema(klass)
          required << name.to_s
        end

        source._nested_manys.each do |name, klass|
          properties[name.to_s] = { type: "array", items: _nested_json_schema(klass) }
        end
      end

      private_class_method :_serialize_fields, :_serialize_form_definition, :_serialize_nested, :_field_to_schema,
        :_coerce_default, :_nested_json_schema, :_add_nested_properties
    end
  end
end
