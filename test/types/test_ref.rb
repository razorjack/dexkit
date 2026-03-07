# frozen_string_literal: true

require "test_helper"

class TestTypesRef < Minitest::Test
  def setup
    setup_test_database
  end

  # === Coercion tests ===

  def test_accepts_model_instance_directly
    model = TestModel.create!(name: "Test")
    ref = Dex::RefType.new(TestModel)
    result = ref.coerce(model)

    assert_equal model, result
    assert_instance_of TestModel, result
  end

  def test_coerces_integer_id_to_record
    model = TestModel.create!(name: "Test")
    ref = Dex::RefType.new(TestModel)
    result = ref.coerce(model.id)

    assert_equal model.id, result.id
    assert_equal model.name, result.name
    assert_instance_of TestModel, result
  end

  def test_coerces_string_id_to_record
    model = TestModel.create!(name: "Test")
    ref = Dex::RefType.new(TestModel)
    result = ref.coerce(model.id.to_s)

    assert_equal model.id, result.id
    assert_equal model.name, result.name
    assert_instance_of TestModel, result
  end

  def test_raises_on_record_not_found
    ref = Dex::RefType.new(TestModel)

    assert_raises(ActiveRecord::RecordNotFound) do
      ref.coerce(99_999)
    end
  end

  # === Type behavior in operations ===

  def test_ref_prop_accepts_model_instance
    model = TestModel.create!(name: "Test")

    op = build_operation do
      prop :model, _Ref(TestModel)
      def perform = model.is_a?(TestModel)
    end

    assert op.new(model: model).call
  end

  def test_ref_prop_coerces_id_to_model
    model = TestModel.create!(name: "Test")

    op = build_operation do
      prop :model, _Ref(TestModel)
      def perform = model
    end

    result = op.new(model: model.id).call
    assert_instance_of TestModel, result
    assert_equal model.id, result.id
  end

  def test_model_methods_work_directly
    model = TestModel.create!(name: "OriginalName")

    op = build_operation do
      prop :model, _Ref(TestModel)
      def perform = model.name
    end

    assert_equal "OriginalName", op.new(model: model).call
  end

  # === Serialization tests ===

  def test_as_json_returns_id_for_ref_props
    model = TestModel.create!(name: "Test")

    op = build_operation do
      prop :model, _Ref(TestModel)
      def perform = nil
    end

    instance = op.new(model: model)
    json = instance.send(:_props_as_json)

    assert_equal({ "model" => model.id }, json)
  end

  def test_non_ref_props_serialize_normally
    model = TestModel.create!(name: "Test")

    op = build_operation do
      prop :model, _Ref(TestModel)
      prop :name, String
      prop :count, Integer
      def perform = nil
    end

    instance = op.new(model: model, name: "TestName", count: 42)
    json = instance.send(:_props_as_json)

    expected = {
      "model" => model.id,
      "name" => "TestName",
      "count" => 42
    }
    assert_equal expected, json
  end

  def test_works_with_prop_and_coercion
    model = TestModel.create!(name: "Test")

    op = define_operation(:TestRefInParams) do
      prop :model, _Ref(TestModel)

      def perform
        model.is_a?(TestModel)
      end
    end

    result = op.new(model: model.id).call
    assert result
  end

  def test_success_type_with_ref
    model = TestModel.create!(name: "Test")

    op = define_operation(:TestRefSuccessType) do
      success _Ref(TestModel)

      define_method(:perform) { model }
    end

    result = op.new.call
    assert_instance_of TestModel, result
    assert_equal model.id, result.id
  end

  def test_recording_saves_ids_not_full_objects
    model = TestModel.create!(name: "Test")

    with_recording do
      op = define_operation(:TestRefRecording) do
        prop :model, _Ref(TestModel)
        success _Ref(TestModel)

        define_method(:perform) { model }
      end

      op.new(model: model.id).call

      record = OperationRecord.last
      assert_equal({ "model" => model.id }, record.params)
      assert_equal model.id, record.result
    end
  end

  # === Lock option tests ===

  def test_lock_option_calls_lock_on_scope
    model = TestModel.create!(name: "Test")

    locked_scope = Minitest::Mock.new
    locked_scope.expect(:find, model, [model.id])

    TestModel.stub(:lock, locked_scope) do
      ref = Dex::RefType.new(TestModel, lock: true)
      result = ref.coerce(model.id)

      assert_equal model, result
    end
    locked_scope.verify
  end

  def test_lock_option_skips_lock_for_instance
    model = TestModel.create!(name: "Test")
    ref = Dex::RefType.new(TestModel, lock: true)
    result = ref.coerce(model)

    assert_equal model, result
  end

  def test_lock_option_skips_lock_for_nil
    ref = Dex::RefType.new(TestModel, lock: true)
    result = ref.coerce(nil)

    assert_nil result
  end

  def test_lock_false_by_default
    model = TestModel.create!(name: "Test")
    ref = Dex::RefType.new(TestModel)

    # Should use model_class.find directly, not lock
    TestModel.stub(:find, model) do
      result = ref.coerce(model.id)
      assert_equal model, result
    end
  end

  # === Optional ref tests ===

  def test_optional_ref_works_with_nil
    op = build_operation do
      prop? :model, _Ref(TestModel)
      def perform = model
    end

    result = op.new(model: nil).call
    assert_nil result
  end

  def test_optional_ref_works_with_instance
    model = TestModel.create!(name: "Test")

    op = build_operation do
      prop? :model, _Ref(TestModel)
      def perform = model
    end

    result = op.new(model: model).call
    assert_equal model, result
    assert_instance_of TestModel, result
  end

  def test_optional_ref_works_with_id
    model = TestModel.create!(name: "Test")

    op = build_operation do
      prop? :model, _Ref(TestModel)
      def perform = model
    end

    result = op.new(model: model.id).call
    assert_equal model.id, result.id
    assert_instance_of TestModel, result
  end

  def test_optional_ref_serializes_nil_correctly
    op = build_operation do
      prop? :model, _Ref(TestModel)
      def perform = nil
    end

    instance = op.new(model: nil)
    json = instance.send(:_props_as_json)
    assert_equal({ "model" => nil }, json)
  end

  # === Case equality (===) ===

  def test_ref_type_matches_model_instance
    model = TestModel.create!(name: "Test")
    ref = Dex::RefType.new(TestModel)

    assert ref === model # rubocop:disable Style/CaseEquality
  end

  def test_ref_type_does_not_match_non_model
    ref = Dex::RefType.new(TestModel)

    refute ref === "not a model" # rubocop:disable Style/CaseEquality
  end
end
