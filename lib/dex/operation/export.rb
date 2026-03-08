# frozen_string_literal: true

module Dex
  class Operation
    module Export
      module_function

      def build_hash(source, contract) # rubocop:disable Metrics/MethodLength
        h = {}
        h[:name] = source.name if source&.name
        desc = source&.description
        h[:description] = desc if desc
        h[:params] = _serialize_params(source, contract.params)
        h[:success] = TypeSerializer.to_string(contract.success) if contract.success
        h[:errors] = contract.errors unless contract.errors.empty?
        h[:guards] = contract.guards unless contract.guards.empty?
        ctx = _serialize_context(source)
        h[:context] = ctx unless ctx.empty?
        h[:pipeline] = source.pipeline.steps.map(&:name) if source
        h[:settings] = _serialize_settings(source) if source
        h
      end

      def build_json_schema(source, contract, section: :params) # rubocop:disable Metrics/MethodLength
        case section
        when :params then _params_schema(source, contract)
        when :success then _success_schema(source, contract)
        when :errors then _errors_schema(source, contract)
        when :full then _full_schema(source, contract)
        else
          raise ArgumentError,
            "unknown section: #{section.inspect}. Known: :params, :success, :errors, :full"
        end
      end

      def _serialize_params(source, params)
        descs = source&.respond_to?(:prop_descriptions) ? source.prop_descriptions : {}
        params.each_with_object({}) do |(name, type), hash|
          entry = { type: TypeSerializer.to_string(type), required: _required?(source, name) }
          entry[:desc] = descs[name] if descs[name]
          hash[name] = entry
        end
      end

      def _required?(source, prop_name)
        return true unless source&.respond_to?(:literal_properties)

        prop = source.literal_properties.find { |p| p.name == prop_name }
        return true unless prop

        prop.required?
      end

      def _serialize_context(source)
        source&.respond_to?(:context_mappings) ? source.context_mappings.presence || {} : {}
      end

      def _serialize_settings(source) # rubocop:disable Metrics/MethodLength
        settings = {}

        record_s = source.settings_for(:record)
        settings[:record] = {
          enabled: record_s.fetch(:enabled, true),
          params: record_s.fetch(:params, true),
          result: record_s.fetch(:result, true)
        }

        tx_s = source.settings_for(:transaction)
        settings[:transaction] = { enabled: tx_s.fetch(:enabled, true) }

        once_s = source.settings_for(:once)
        settings[:once] = { defined: once_s.fetch(:defined, false) }

        settings
      end

      def _params_schema(source, contract) # rubocop:disable Metrics/MethodLength
        descs = source&.respond_to?(:prop_descriptions) ? source.prop_descriptions : {}
        properties = {}
        required = []

        contract.params.each do |name, type|
          prop_desc = descs[name]
          schema = TypeSerializer.to_json_schema(type, desc: prop_desc)
          properties[name.to_s] = schema
          required << name.to_s if _required?(source, name)
        end

        result = { "$schema": "https://json-schema.org/draft/2020-12/schema", type: "object" }
        result[:title] = source.name if source&.name
        desc = source&.description
        result[:description] = desc if desc
        result[:properties] = properties unless properties.empty?
        result[:required] = required unless required.empty?
        result[:additionalProperties] = false
        result
      end

      def _success_schema(source, contract)
        return {} unless contract.success

        schema = TypeSerializer.to_json_schema(contract.success)
        result = { "$schema": "https://json-schema.org/draft/2020-12/schema" }
        result[:title] = "#{source&.name} success" if source&.name
        result.merge(schema)
      end

      def _errors_schema(source, contract)
        result = { "$schema": "https://json-schema.org/draft/2020-12/schema" }
        result[:title] = "#{source&.name} errors" if source&.name
        result[:type] = "object"

        properties = {}
        contract.errors.each do |code|
          properties[code.to_s] = {
            type: "object",
            properties: {
              code: { const: code.to_s },
              message: { type: "string" },
              details: { type: "object" }
            }
          }
        end
        result[:properties] = properties unless properties.empty?
        result
      end

      def _full_schema(source, contract)
        result = { "$schema": "https://json-schema.org/draft/2020-12/schema" }
        result[:title] = source.name if source&.name
        result[:description] = "Operation contract"
        result[:properties] = {
          params: _params_schema(source, contract).except(:$schema),
          success: _success_schema(source, contract).except(:$schema),
          errors: _errors_schema(source, contract).except(:$schema)
        }
        result
      end

      private_class_method :_serialize_params, :_required?, :_serialize_context, :_serialize_settings,
        :_params_schema, :_success_schema, :_errors_schema, :_full_schema
    end
  end
end
