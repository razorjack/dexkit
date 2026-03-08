# frozen_string_literal: true

require "test_helper"

class TestTypeSerializer < Minitest::Test
  include Literal::Types

  # --- to_string ---

  def test_string_type
    assert_equal "String", Dex::TypeSerializer.to_string(String)
  end

  def test_integer_type
    assert_equal "Integer", Dex::TypeSerializer.to_string(Integer)
  end

  def test_float_type
    assert_equal "Float", Dex::TypeSerializer.to_string(Float)
  end

  def test_boolean_type
    assert_equal "Boolean", Dex::TypeSerializer.to_string(_Boolean)
  end

  def test_nilable_type
    assert_equal "Nilable(String)", Dex::TypeSerializer.to_string(_Nilable(String))
  end

  def test_array_type
    assert_equal "Array(String)", Dex::TypeSerializer.to_string(_Array(String))
  end

  def test_union_of_types
    assert_equal "Union(String, Integer)", Dex::TypeSerializer.to_string(_Union(String, Integer))
  end

  def test_union_of_values
    result = Dex::TypeSerializer.to_string(_Union("a", "b"))
    assert_match(/Union/, result)
    assert_match(/"a"/, result)
    assert_match(/"b"/, result)
  end

  def test_ref_type
    model = Class.new { def self.name = "Product" }
    ref = Dex::RefType.new(model)
    assert_equal "Ref(Product)", Dex::TypeSerializer.to_string(ref)
  end

  def test_constrained_integer
    result = Dex::TypeSerializer.to_string(_Integer(1..))
    assert_equal "Integer(1..)", result
  end

  def test_constrained_integer_range
    result = Dex::TypeSerializer.to_string(_Integer(1..100))
    assert_equal "Integer(1..100)", result
  end

  def test_nested_nilable_array
    result = Dex::TypeSerializer.to_string(_Nilable(_Array(Integer)))
    assert_equal "Nilable(Array(Integer))", result
  end

  # --- to_json_schema ---

  def test_schema_string
    assert_equal({ type: "string" }, Dex::TypeSerializer.to_json_schema(String))
  end

  def test_schema_integer
    assert_equal({ type: "integer" }, Dex::TypeSerializer.to_json_schema(Integer))
  end

  def test_schema_float
    assert_equal({ type: "number" }, Dex::TypeSerializer.to_json_schema(Float))
  end

  def test_schema_boolean_true
    assert_equal({ type: "boolean" }, Dex::TypeSerializer.to_json_schema(TrueClass))
  end

  def test_schema_boolean_false
    assert_equal({ type: "boolean" }, Dex::TypeSerializer.to_json_schema(FalseClass))
  end

  def test_schema_boolean_type
    assert_equal({ type: "boolean" }, Dex::TypeSerializer.to_json_schema(_Boolean))
  end

  def test_schema_symbol
    assert_equal({ type: "string" }, Dex::TypeSerializer.to_json_schema(Symbol))
  end

  def test_schema_hash
    assert_equal({ type: "object" }, Dex::TypeSerializer.to_json_schema(Hash))
  end

  def test_schema_date
    assert_equal({ type: "string", format: "date" }, Dex::TypeSerializer.to_json_schema(Date))
  end

  def test_schema_time
    assert_equal({ type: "string", format: "date-time" }, Dex::TypeSerializer.to_json_schema(Time))
  end

  def test_schema_datetime
    assert_equal({ type: "string", format: "date-time" }, Dex::TypeSerializer.to_json_schema(DateTime))
  end

  def test_schema_bigdecimal
    schema = Dex::TypeSerializer.to_json_schema(BigDecimal)
    assert_equal "string", schema[:type]
    assert schema.key?(:pattern)
  end

  def test_schema_nilable
    schema = Dex::TypeSerializer.to_json_schema(_Nilable(String))
    assert_equal [{ type: "string" }, { type: "null" }], schema[:oneOf]
  end

  def test_schema_array
    schema = Dex::TypeSerializer.to_json_schema(_Array(Integer))
    assert_equal "array", schema[:type]
    assert_equal({ type: "integer" }, schema[:items])
  end

  def test_schema_union_values
    schema = Dex::TypeSerializer.to_json_schema(_Union("a", "b"))
    assert_equal %w[a b], schema[:enum].sort
  end

  def test_schema_union_types
    schema = Dex::TypeSerializer.to_json_schema(_Union(String, Integer))
    assert_equal [{ type: "string" }, { type: "integer" }], schema[:oneOf]
  end

  def test_schema_ref
    model = Class.new { def self.name = "Order" }
    ref = Dex::RefType.new(model)
    schema = Dex::TypeSerializer.to_json_schema(ref)
    assert_equal "string", schema[:type]
    assert_equal "Order ID", schema[:description]
  end

  def test_schema_ref_desc_override
    model = Class.new { def self.name = "Order" }
    ref = Dex::RefType.new(model)
    schema = Dex::TypeSerializer.to_json_schema(ref, desc: "The order")
    assert_equal "The order", schema[:description]
  end

  def test_schema_constrained_integer_minimum
    schema = Dex::TypeSerializer.to_json_schema(_Integer(1..))
    assert_equal "integer", schema[:type]
    assert_equal 1, schema[:minimum]
  end

  def test_schema_constrained_integer_range
    schema = Dex::TypeSerializer.to_json_schema(_Integer(1..100))
    assert_equal 1, schema[:minimum]
    assert_equal 100, schema[:maximum]
  end

  def test_schema_unknown_type
    assert_equal({}, Dex::TypeSerializer.to_json_schema(Object))
  end

  def test_schema_desc_kwarg
    schema = Dex::TypeSerializer.to_json_schema(String, desc: "A name")
    assert_equal "A name", schema[:description]
  end
end
