# frozen_string_literal: true

require "test_helper"

class TestTypesRecord < Minitest::Test
  def setup
    setup_test_database
  end

  # === Coercion tests ===

  def test_accepts_model_instance_directly
    model = TestModel.create!(name: "Test")
    type = Types::Record(TestModel)
    result = type[model]

    assert_equal model, result
    assert_instance_of TestModel, result
  end

  def test_coerces_integer_id_to_record
    model = TestModel.create!(name: "Test")
    type = Types::Record(TestModel)
    result = type[model.id]

    assert_equal model.id, result.id
    assert_equal model.name, result.name
    assert_instance_of TestModel, result
  end

  def test_coerces_string_id_to_record
    model = TestModel.create!(name: "Test")
    type = Types::Record(TestModel)
    result = type[model.id.to_s]

    assert_equal model.id, result.id
    assert_equal model.name, result.name
    assert_instance_of TestModel, result
  end

  def test_raises_on_record_not_found
    type = Types::Record(TestModel)

    assert_raises(ActiveRecord::RecordNotFound) do
      type[99_999]
    end
  end

  # === Type behavior tests ===

  def test_is_a_check_returns_true
    model = TestModel.create!(name: "Test")

    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel)
    end

    params = params_class.new(model: model)

    assert params.model.is_a?(TestModel)
  end

  def test_model_methods_work_directly
    model = TestModel.create!(name: "OriginalName")

    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel)
    end

    params = params_class.new(model: model)

    # Can call model methods
    assert_equal "OriginalName", params.model.name

    # Can update the model
    params.model.update!(name: "UpdatedName")
    assert_equal "UpdatedName", params.model.reload.name
  end

  def test_respond_to_works_correctly
    model = TestModel.create!(name: "Test")

    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel)
    end

    params = params_class.new(model: model)

    assert params.model.respond_to?(:name)
    assert params.model.respond_to?(:update!)
    refute params.model.respond_to?(:nonexistent_method)
  end

  # === Serialization tests ===

  def test_as_json_returns_id_for_record_attributes
    model = TestModel.create!(name: "Test")

    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel)
    end

    params = params_class.new(model: model)

    assert_equal({"model" => model.id}, params.as_json)
  end

  def test_non_record_attributes_serialize_normally
    model = TestModel.create!(name: "Test")

    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel)
      attribute :name, Types::String
      attribute :count, Types::Integer
    end

    params = params_class.new(model: model, name: "TestName", count: 42)

    expected = {
      "model" => model.id,
      "name" => "TestName",
      "count" => 42
    }
    assert_equal expected, params.as_json
  end

  def test_works_in_params_block
    model = TestModel.create!(name: "Test")

    op = define_operation(:TestRecordInParams) do
      params do
        attribute :model, Types::Record(TestModel)
      end

      def perform
        params.model.is_a?(TestModel)
      end
    end

    result = op.new(model: model.id).perform
    assert result
  end

  def test_works_in_result_block
    model = TestModel.create!(name: "Test")
    model_id = model.id

    op = define_operation(:TestRecordInResult) do
      result do
        attribute :model, Types::Record(TestModel)
      end

      define_method(:perform) do
        {model: model_id}
      end
    end

    result = op.new.perform
    assert_instance_of TestModel, result.model
    assert_equal model.id, result.model.id
  end

  def test_recording_saves_ids_not_full_objects
    model = TestModel.create!(name: "Test")

    with_recording do
      op = define_operation(:TestRecordRecording) do
        params do
          attribute :model, Types::Record(TestModel)
        end

        result do
          attribute :model, Types::Record(TestModel)
        end

        def perform
          {model: params.model}
        end
      end

      op.new(model: model.id).perform

      record = OperationRecord.last
      assert_equal({"model" => model.id}, record.params)
      assert_equal({"model" => model.id}, record.response)
    end
  end

  # === Optional type tests ===

  def test_optional_works_with_nil
    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel).optional
    end

    params = params_class.new(model: nil)
    assert_nil params.model
  end

  def test_optional_works_with_instance
    model = TestModel.create!(name: "Test")

    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel).optional
    end

    params = params_class.new(model: model)
    assert_equal model, params.model
    assert_instance_of TestModel, params.model
  end

  def test_optional_works_with_id
    model = TestModel.create!(name: "Test")

    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel).optional
    end

    params = params_class.new(model: model.id)
    assert_equal model.id, params.model.id
    assert_instance_of TestModel, params.model
  end

  def test_optional_serializes_nil_correctly
    params_class = Class.new(Dex::Parameters) do
      attribute :model, Types::Record(TestModel).optional
    end

    params = params_class.new(model: nil)
    assert_equal({"model" => nil}, params.as_json)
  end
end
