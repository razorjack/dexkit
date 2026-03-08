# frozen_string_literal: true

module Dex
  module Tool
    module_function

    def from(operation_class)
      _require_ruby_llm!
      _build_tool(operation_class)
    end

    def all
      _require_ruby_llm!
      Operation.registry.sort_by(&:name).map { |klass| _build_tool(klass) }
    end

    def from_namespace(namespace)
      _require_ruby_llm!
      prefix = "#{namespace}::"
      Operation.registry
        .select { |op| op.name&.start_with?(prefix) }
        .sort_by(&:name)
        .map { |klass| _build_tool(klass) }
    end

    def explain_tool
      _require_ruby_llm!
      _build_explain_tool
    end

    def _require_ruby_llm!
      require "ruby_llm"
    rescue LoadError
      raise LoadError,
        "Dex::Tool requires the ruby-llm gem. Add `gem 'ruby_llm'` to your Gemfile."
    end

    def _build_tool(operation_class) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
      op = operation_class
      schema = op.contract.to_json_schema
      tool_description = _tool_description(op)

      Class.new(RubyLLM::Tool) do
        define_method(:name) { "dex_#{op.name.gsub("::", "_").downcase}" }
        define_method(:description) { tool_description }
        define_method(:params) { schema }

        define_method(:execute) do |**params|
          coerced = params.transform_keys(&:to_sym)
          result = op.new(**coerced).safe.call
          case result
          when Dex::Operation::Ok
            value = result.value
            value.respond_to?(:as_json) ? value.as_json : value
          when Dex::Operation::Err
            { error: result.code, message: result.message, details: result.details }
          end
        end
      end.new
    end

    def _tool_description(op)
      parts = []
      desc = op.description
      parts << desc if desc
      parts << op.name unless desc

      guards = op.contract.guards
      if guards.any?
        messages = guards.map { |g| g[:message] || g[:name].to_s }
        parts << "Preconditions: #{messages.join("; ")}."
      end

      errors = op.contract.errors
      parts << "Errors: #{errors.join(", ")}." if errors.any?

      parts.join("\n")
    end

    def _build_explain_tool # rubocop:disable Metrics/MethodLength
      Class.new(RubyLLM::Tool) do
        define_method(:name) { "dex_explain" }
        define_method(:description) { "Check if an operation can be executed with given params, without running it." }
        define_method(:params) do
          {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            type: "object",
            properties: {
              "operation" => { type: "string", description: "Operation class name (e.g. 'Order::Place')" },
              "params" => { type: "object", description: "Params to check" }
            },
            required: ["operation"],
            additionalProperties: false
          }
        end

        define_method(:execute) do |operation:, params: {}|
          op_class = Dex::Operation.registry.find { |klass| klass.name == operation }
          return { error: "unknown_operation", message: "Operation '#{operation}' not found in registry" } unless op_class

          coerced = params.transform_keys(&:to_sym)
          info = op_class.explain(**coerced)
          {
            callable: info[:callable],
            guards: info[:guards],
            once: info[:once],
            lock: info[:lock]
          }
        end
      end.new
    end

    private_class_method :_require_ruby_llm!, :_build_tool, :_tool_description, :_build_explain_tool
  end
end
