# frozen_string_literal: true

require "test_helper"

class TestOperationOutcome < Minitest::Test
  def setup
    setup_test_database
  end

  # Ok tests
  def test_ok_wraps_value
    ok = Dex::Operation::Ok.new({ id: 1, name: "Test" })
    assert ok.ok?
    refute ok.error?
    assert_equal({ id: 1, name: "Test" }, ok.value)
    assert_equal({ id: 1, name: "Test" }, ok.value!)
  end

  def test_ok_delegates_to_value
    result = Class.new do
      attr_reader :id, :name
      def initialize(id:, name:)
        @id = id
        @name = name
      end
    end.new(id: 1, name: "Test")

    ok = Dex::Operation::Ok.new(result)
    assert_equal 1, ok.id
    assert_equal "Test", ok.name
  end

  def test_ok_deconstruct_keys_with_hash
    ok = Dex::Operation::Ok.new({ id: 1, name: "Test" })

    case ok
    in { id: 1, name: }
      assert_equal "Test", name
    else
      flunk "Pattern matching failed"
    end
  end

  def test_ok_deconstruct_keys_with_struct
    result_struct = Struct.new(:id, :name, keyword_init: true)
    ok = Dex::Operation::Ok.new(result_struct.new(id: 1, name: "Test"))

    case ok
    in { id: 1, name: }
      assert_equal "Test", name
    else
      flunk "Pattern matching failed"
    end
  end

  # Err tests
  def test_err_wraps_error
    error = Dex::Error.new(:not_found, "Record not found")
    err = Dex::Operation::Err.new(error)

    refute err.ok?
    assert err.error?
    assert_nil err.value
  end

  def test_err_value_bang_raises
    error = Dex::Error.new(:not_found, "Record not found")
    err = Dex::Operation::Err.new(error)

    raised = assert_raises(Dex::Error) do
      err.value!
    end

    assert_equal error, raised
  end

  def test_err_accessors
    error = Dex::Error.new(:validation_failed, "Invalid input", details: { field: "email" })
    err = Dex::Operation::Err.new(error)

    assert_equal :validation_failed, err.code
    assert_equal "Invalid input", err.message
    assert_equal({ field: "email" }, err.details)
  end

  def test_err_deconstruct_keys
    error = Dex::Error.new(:duplicate, "Already exists", details: { id: 123 })
    err = Dex::Operation::Err.new(error)

    case err
    in { code: :duplicate, message:, details: }
      assert_equal "Already exists", message
      assert_equal({ id: 123 }, details)
    else
      flunk "Pattern matching failed"
    end
  end

  # Safe modifier tests
  def test_safe_returns_ok_on_success
    op = operation do
      { status: "success" }
    end

    outcome = op.new.safe.call
    assert_instance_of Dex::Operation::Ok, outcome
    assert outcome.ok?
    assert_equal({ status: "success" }, outcome.value)
  end

  def test_safe_returns_err_on_error
    op = operation do
      error!(:failure, "Something went wrong")
    end

    outcome = op.new.safe.call
    assert_instance_of Dex::Operation::Err, outcome
    assert outcome.error?
    assert_equal :failure, outcome.code
    assert_equal "Something went wrong", outcome.message
  end

  def test_safe_with_result_schema
    op = operation(result: { id: Types::Integer, status: Types::String }) do
      { id: 1, status: "completed" }
    end

    outcome = op.new.safe.call
    assert outcome.ok?
    assert_instance_of op::Result, outcome.value
    assert_equal 1, outcome.id
    assert_equal "completed", outcome.status
  end

  def test_safe_pattern_matching_success
    op = operation(result: { user_id: Types::Integer }) do
      { user_id: 42 }
    end

    outcome = op.new.safe.call

    case outcome
    in Dex::Ok(user_id: id)
      assert_equal 42, id
    in Dex::Err
      flunk "Should not match Err"
    end
  end

  def test_safe_pattern_matching_failure
    op = operation do
      error!(:unauthorized, "Access denied")
    end

    outcome = op.new.safe.call

    case outcome
    in Dex::Ok
      flunk "Should not match Ok"
    in Dex::Err(code: :unauthorized, message:)
      assert_equal "Access denied", message
    end
  end

  # Top-level aliases
  def test_top_level_aliases
    assert_equal Dex::Operation::Ok, Dex::Ok
    assert_equal Dex::Operation::Err, Dex::Err
  end

  def test_match_module_provides_ok_and_err
    test_class = Class.new do
      include Dex::Match
    end

    instance = test_class.new
    assert_equal Dex::Ok, instance.class::Ok
    assert_equal Dex::Err, instance.class::Err
  end

  # Integration test
  def test_safe_with_params_and_result
    op = operation(params: { value: Types::Integer }, result: { doubled: Types::Integer }) do
      if params.value < 0
        error!(:invalid_value, "Value must be positive")
      else
        { doubled: params.value * 2 }
      end
    end

    # Success case
    success = op.new(value: 5).safe.call
    assert success.ok?
    assert_equal 10, success.doubled

    # Failure case
    failure = op.new(value: -1).safe.call
    assert failure.error?
    assert_equal :invalid_value, failure.code
  end
end
