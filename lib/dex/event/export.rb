# frozen_string_literal: true

module Dex
  class Event
    module Export
      module_function

      def build_hash(source)
        h = {}
        h[:name] = source.name if source.name
        desc = source.description
        h[:description] = desc if desc
        h[:props] = _serialize_props(source)
        h
      end

      def build_json_schema(source)
        descs = source.respond_to?(:prop_descriptions) ? source.prop_descriptions : {}
        properties = {}
        required = []

        if source.respond_to?(:literal_properties)
          source.literal_properties.each do |prop|
            prop_desc = descs[prop.name]
            schema = TypeSerializer.to_json_schema(prop.type, desc: prop_desc)
            properties[prop.name.to_s] = schema
            required << prop.name.to_s if prop.required?
          end
        end

        result = { "$schema": "https://json-schema.org/draft/2020-12/schema" }
        result[:title] = source.name if source.name
        desc = source.description
        result[:description] = desc if desc
        result[:type] = "object"
        result[:properties] = properties unless properties.empty?
        result[:required] = required unless required.empty?
        result[:additionalProperties] = false
        result
      end

      def _serialize_props(source)
        return {} unless source.respond_to?(:literal_properties)

        descs = source.respond_to?(:prop_descriptions) ? source.prop_descriptions : {}
        source.literal_properties.each_with_object({}) do |prop, hash|
          entry = { type: TypeSerializer.to_string(prop.type), required: prop.required? }
          entry[:desc] = descs[prop.name] if descs[prop.name]
          hash[prop.name] = entry
        end
      end

      private_class_method :_serialize_props
    end
  end
end
