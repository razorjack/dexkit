# frozen_string_literal: true

require "test_helper"

class TestFormExport < Minitest::Test
  def teardown
    Dex::Form.clear!
    super
  end

  # --- Class-level to_h ---

  def test_to_h_basic
    form_class = define_form(:ExportBasicForm) do
      description "Basic form"
      field :name, :string, desc: "Full name"
      field :age, :integer
      field? :notes, :string
    end

    h = form_class.to_h
    assert_equal "ExportBasicForm", h[:name]
    assert_equal "Basic form", h[:description]

    assert_equal :string, h[:fields][:name][:type]
    assert h[:fields][:name][:required]
    assert_equal "Full name", h[:fields][:name][:desc]

    assert_equal :integer, h[:fields][:age][:type]
    assert h[:fields][:age][:required]

    assert_equal :string, h[:fields][:notes][:type]
    refute h[:fields][:notes][:required]
  end

  def test_to_h_with_default
    form_class = build_form do
      field :currency, :string, default: "USD"
      field? :priority, :integer, default: 0
    end

    h = form_class.to_h
    assert_equal "USD", h[:fields][:currency][:default]
    assert_equal 0, h[:fields][:priority][:default]
  end

  def test_to_h_without_default
    form_class = build_form do
      field :name, :string
      field? :notes, :string
    end

    h = form_class.to_h
    refute h[:fields][:name].key?(:default)
    refute h[:fields][:notes].key?(:default)
  end

  def test_to_h_with_nested
    form_class = build_form do
      field :name, :string

      nested_one :address do
        field :street, :string
        field :city, :string
        field? :apartment, :string
      end

      nested_many :documents do
        field :doc_type, :string
      end
    end

    h = form_class.to_h
    assert_equal :one, h[:nested][:address][:type]
    assert_equal :string, h[:nested][:address][:fields][:street][:type]
    assert h[:nested][:address][:fields][:street][:required]
    refute h[:nested][:address][:fields][:apartment][:required]

    assert_equal :many, h[:nested][:documents][:type]
    assert_equal :string, h[:nested][:documents][:fields][:doc_type][:type]
  end

  def test_to_h_deeply_nested
    form_class = build_form do
      nested_one :address do
        field :street, :string

        nested_one :coordinate do
          field :lat, :float
          field :lng, :float
        end
      end
    end

    h = form_class.to_h
    assert_equal :one, h[:nested][:address][:type]
    assert_equal :one, h[:nested][:address][:nested][:coordinate][:type]
    assert_equal :float, h[:nested][:address][:nested][:coordinate][:fields][:lat][:type]
  end

  def test_to_h_no_nested_key_when_empty
    form_class = build_form do
      field :name, :string
    end

    h = form_class.to_h
    refute h.key?(:nested)
  end

  # --- Class-level to_json_schema ---

  def test_to_json_schema_basic
    form_class = define_form(:SchemaBasicForm) do
      description "Schema form"
      field :email, :string, desc: "Customer email"
      field :amount, :decimal
      field? :notes, :string
    end

    schema = form_class.to_json_schema
    assert_equal "https://json-schema.org/draft/2020-12/schema", schema[:$schema]
    assert_equal "object", schema[:type]
    assert_equal "SchemaBasicForm", schema[:title]
    assert_equal "Schema form", schema[:description]

    assert_equal({ type: "string", description: "Customer email" },
      schema[:properties]["email"])
    assert_equal({ type: "number" }, schema[:properties]["amount"])
    assert_equal({ type: "string" }, schema[:properties]["notes"])

    assert_includes schema[:required], "email"
    assert_includes schema[:required], "amount"
    refute_includes schema[:required], "notes"

    assert_equal false, schema[:additionalProperties]
  end

  def test_to_json_schema_type_mapping
    form_class = build_form do
      field :s, :string
      field :i, :integer
      field :f, :float
      field :d, :decimal
      field :b, :boolean
      field :dt, :date
      field :dtt, :datetime
      field :t, :time
    end

    schema = form_class.to_json_schema
    assert_equal "string", schema[:properties]["s"][:type]
    assert_equal "integer", schema[:properties]["i"][:type]
    assert_equal "number", schema[:properties]["f"][:type]
    assert_equal "number", schema[:properties]["d"][:type]
    assert_equal "boolean", schema[:properties]["b"][:type]
    assert_equal "date", schema[:properties]["dt"][:format]
    assert_equal "date-time", schema[:properties]["dtt"][:format]
    assert_equal "time", schema[:properties]["t"][:format]
  end

  def test_to_json_schema_with_default
    form_class = build_form do
      field :currency, :string, default: "USD"
    end

    schema = form_class.to_json_schema
    assert_equal "USD", schema[:properties]["currency"][:default]
  end

  def test_to_json_schema_coerces_defaults
    form_class = build_form do
      field :amount, :decimal, default: BigDecimal("9.99")
      field :count, :integer, default: 0
      field :active, :boolean, default: true
    end

    schema = form_class.to_json_schema
    assert_equal 9.99, schema[:properties]["amount"][:default]
    assert_instance_of Float, schema[:properties]["amount"][:default]
    assert_equal 0, schema[:properties]["count"][:default]
    assert_equal true, schema[:properties]["active"][:default]
  end

  def test_to_json_schema_nested_one
    form_class = build_form do
      field :name, :string

      nested_one :address do
        field :street, :string
        field :city, :string
        field? :apartment, :string
      end
    end

    schema = form_class.to_json_schema
    address_schema = schema[:properties]["address"]
    assert_equal "object", address_schema[:type]
    assert_equal "string", address_schema[:properties]["street"][:type]
    assert_includes address_schema[:required], "street"
    assert_includes address_schema[:required], "city"
    refute_includes address_schema[:required], "apartment"
    # nested_one is required in the parent
    assert_includes schema[:required], "address"
  end

  def test_to_json_schema_nested_many
    form_class = build_form do
      nested_many :documents do
        field :doc_type, :string
      end
    end

    schema = form_class.to_json_schema
    docs_schema = schema[:properties]["documents"]
    assert_equal "array", docs_schema[:type]
    assert_equal "object", docs_schema[:items][:type]
    assert_equal "string", docs_schema[:items][:properties]["doc_type"][:type]
  end

  def test_to_json_schema_deeply_nested
    form_class = build_form do
      field :name, :string

      nested_one :address do
        field :city, :string

        nested_one :coordinate do
          field :lat, :float
          field :lng, :float
        end
      end
    end

    schema = form_class.to_json_schema
    coord_schema = schema[:properties]["address"][:properties]["coordinate"]
    assert_equal "object", coord_schema[:type]
    assert_equal "number", coord_schema[:properties]["lat"][:type]
  end

  def test_to_json_schema_nested_strict
    form_class = build_form do
      field :name, :string

      nested_one :address do
        field :street, :string
      end

      nested_many :tags do
        field :label, :string
      end
    end

    schema = form_class.to_json_schema
    assert_equal false, schema[:properties]["address"][:additionalProperties]
    assert_equal false, schema[:properties]["tags"][:items][:additionalProperties]
  end

  # --- Global export ---

  def test_export_hash
    define_form(:ExportAForm) { field :a, :string }
    define_form(:ExportBForm) { field :b, :string }

    result = Dex::Form.export(format: :hash)
    assert_equal 2, result.size
    names = result.map { |h| h[:name] }
    assert_includes names, "ExportAForm"
    assert_includes names, "ExportBForm"
  end

  def test_export_json_schema
    define_form(:SchemaExportForm) do
      field :name, :string
    end

    result = Dex::Form.export(format: :json_schema)
    assert result.all? { |s| s[:type] == "object" }
  end

  def test_export_excludes_nested_helper_forms
    define_form(:ExportParentForm) do
      field :name, :string

      nested_one :address do
        field :street, :string
      end
    end

    result = Dex::Form.export(format: :hash)
    names = result.map { |h| h[:name] }
    assert_includes names, "ExportParentForm"
    refute_includes names, "ExportParentForm::Address"
  end

  def test_export_invalid_format
    err = assert_raises(ArgumentError) do
      Dex::Form.export(format: :xml)
    end
    assert_match(/unknown format/, err.message)
  end

  # --- Instance-level to_h unchanged ---

  def test_instance_to_h_still_works
    form_class = build_form do
      field :name, :string
      field :age, :integer
    end

    form = form_class.new(name: "Alice", age: 30)
    assert_equal({ name: "Alice", age: 30 }, form.to_h)
  end
end
