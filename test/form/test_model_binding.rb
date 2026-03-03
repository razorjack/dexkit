# frozen_string_literal: true

require "test_helper"

class TestFormModelBinding < Minitest::Test
  def setup
    setup_test_database
  end

  def test_model_sets_model_class
    form_class = define_form(:UserForm) do
      model TestModel
    end

    assert_equal TestModel, form_class._model_class
  end

  def test_model_validates_argument
    assert_raises(ArgumentError) do
      build_form do
        model "NotAClass"
      end
    end
  end

  def test_model_class_inherited
    parent = define_form(:ParentModelForm) do
      model TestModel
    end

    child = define_form(:ChildModelForm, parent: parent)

    assert_equal TestModel, child._model_class
  end

  def test_record_accessor
    form_class = build_form do
      attribute :name, :string
    end

    record = TestModel.create!(name: "Alice")
    form = form_class.new(name: "Alice", record: record)
    assert_equal record, form.record
  end

  def test_persisted_with_persisted_record
    form_class = build_form do
      attribute :name, :string
    end

    record = TestModel.create!(name: "Alice")
    form = form_class.new(name: "Alice", record: record)
    assert form.persisted?
  end

  def test_persisted_without_record
    form_class = build_form do
      attribute :name, :string
    end

    form = form_class.new(name: "Alice")
    refute form.persisted?
  end

  def test_persisted_with_new_record
    form_class = build_form do
      attribute :name, :string
    end

    record = TestModel.new(name: "Alice")
    form = form_class.new(name: "Alice", record: record)
    refute form.persisted?
  end

  def test_model_name_delegates_to_model_class
    form_class = define_form(:UserModelForm) do
      model TestModel
      attribute :name, :string
    end

    form = form_class.new(name: "Alice")
    assert_equal "TestModel", form.model_name.name
  end

  def test_model_name_without_model_class
    form_class = define_form(:RegistrationModelForm) do
      attribute :name, :string
    end

    form = form_class.new(name: "Alice")
    assert_equal "RegistrationModelForm", form.model_name.name
  end

  def test_to_key_delegates_to_record
    form_class = build_form do
      attribute :name, :string
    end

    record = TestModel.create!(name: "Alice")
    form = form_class.new(name: "Alice", record: record)
    assert_equal record.to_key, form.to_key
  end

  def test_to_key_nil_without_record
    form_class = build_form do
      attribute :name, :string
    end

    form = form_class.new(name: "Alice")
    assert_nil form.to_key
  end

  def test_to_param_delegates_to_record
    form_class = build_form do
      attribute :name, :string
    end

    record = TestModel.create!(name: "Alice")
    form = form_class.new(name: "Alice", record: record)
    assert_equal record.to_param, form.to_param
  end

  def test_with_record_returns_self
    form_class = build_form do
      attribute :name, :string
    end

    form = form_class.new(name: "Alice")
    assert_same form, form.with_record(TestModel.new)
  end

  def test_with_record_sets_persisted
    form_class = build_form do
      attribute :name, :string
    end

    record = TestModel.create!(name: "Alice")
    form = form_class.new(name: "Alice").with_record(record)
    assert form.persisted?
  end

  def test_with_record_delegates_to_key
    form_class = build_form do
      attribute :name, :string
    end

    record = TestModel.create!(name: "Alice")
    form = form_class.new(name: "Alice").with_record(record)
    assert_equal record.to_key, form.to_key
    assert_equal record.to_param, form.to_param
  end

  def test_record_via_constructor_hash
    form_class = build_form do
      attribute :name, :string
    end

    record = TestModel.create!(name: "Alice")
    form = form_class.new(name: "Alice", record: record)
    assert_equal record, form.record
    assert form.persisted?
  end
end
