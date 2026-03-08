# frozen_string_literal: true

module Dex
  module TypeSerializer
    module_function

    # --- Human-readable string ---

    def to_string(type)
      case type
      when Dex::RefType
        "Ref(#{type.model_class.name})"
      when Literal::Types::NilableType
        "Nilable(#{to_string(type.type)})"
      when Literal::Types::ArrayType
        "Array(#{to_string(type.type)})"
      when Literal::Types::UnionType
        _union_string(type)
      when Literal::Types::ConstraintType
        _constraint_string(type)
      when Literal::Types::BooleanType
        "Boolean"
      when Class
        type.name || type.to_s
      else
        type.inspect
      end
    end

    # --- JSON Schema ---

    BIGDECIMAL_PATTERN = '^-?\d+\.?\d*$'

    def to_json_schema(type, desc: nil)
      schema = _type_to_schema(type)
      schema[:description] = desc if desc
      schema
    end

    def _type_to_schema(type) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity
      case type
      when Dex::RefType
        { type: "string", description: "#{type.model_class.name} ID" }
      when Literal::Types::NilableType
        { oneOf: [_type_to_schema(type.type), { type: "null" }] }
      when Literal::Types::ArrayType
        { type: "array", items: _type_to_schema(type.type) }
      when Literal::Types::UnionType
        _union_schema(type)
      when Literal::Types::ConstraintType
        _constraint_schema(type)
      when Literal::Types::BooleanType
        { type: "boolean" }
      when Class
        _class_schema(type)
      else
        {}
      end
    end

    def _union_string(type)
      items = if type.primitives&.any?
        type.primitives.map(&:inspect)
      else
        type.types.map { |t| to_string(t) }
      end
      "Union(#{items.join(", ")})"
    end

    def _constraint_string(type)
      constraints = type.object_constraints
      return "{}" if constraints.empty?

      base = constraints.first
      rest = constraints[1..]
      base_str = base.is_a?(Class) ? (base.name || base.to_s) : base.inspect
      if rest.empty?
        base_str
      else
        "#{base_str}(#{rest.map(&:inspect).join(", ")})"
      end
    end

    def _union_schema(type)
      if type.primitives&.any?
        { enum: type.primitives.to_a }
      else
        { oneOf: type.types.map { |t| _type_to_schema(t) } }
      end
    end

    def _constraint_schema(type)
      constraints = type.object_constraints
      return {} if constraints.empty?

      base = constraints.first
      schema = base.is_a?(Class) ? _class_schema(base) : {}
      _apply_range_constraints(schema, constraints[1..])
      schema
    end

    def _apply_range_constraints(schema, constraints)
      constraints.each do |c|
        next unless c.is_a?(Range)

        schema[:minimum] = c.begin if c.begin
        if c.end
          schema[c.exclude_end? ? :exclusiveMaximum : :maximum] = c.end
        end
      end
    end

    def _class_schema(type) # rubocop:disable Metrics/MethodLength
      case type.name
      when "String" then { type: "string" }
      when "Integer" then { type: "integer" }
      when "Float" then { type: "number" }
      when "TrueClass", "FalseClass" then { type: "boolean" }
      when "Symbol" then { type: "string" }
      when "Hash" then { type: "object" }
      when "Date" then { type: "string", format: "date" }
      when "Time" then { type: "string", format: "date-time" }
      when "DateTime" then { type: "string", format: "date-time" }
      when "BigDecimal" then { type: "string", pattern: BIGDECIMAL_PATTERN }
      else {}
      end
    end

    private_class_method :_type_to_schema, :_union_string, :_constraint_string,
      :_union_schema, :_constraint_schema, :_apply_range_constraints, :_class_schema
  end
end
