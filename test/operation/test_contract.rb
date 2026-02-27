# frozen_string_literal: true

require "test_helper"

class TestOperationContract < Minitest::Test
  def test_full_contract
    op = operation(
      params: { email: Types::String, name: Types::String },
      success: Types::String,
      errors: %i[email_taken invalid_email]
    )

    c = op.contract
    assert_equal %i[email name], c.params.keys
    assert_equal Types::String, c.success
    assert_equal %i[email_taken invalid_email], c.errors
  end

  def test_empty_operation_returns_defaults
    op = build_operation

    c = op.contract
    assert_equal({}, c.params)
    assert_nil c.success
    assert_equal [], c.errors
  end

  def test_params_only
    op = operation(params: { age: Types::Integer })

    c = op.contract
    assert_equal [:age], c.params.keys
    assert_nil c.success
    assert_equal [], c.errors
  end

  def test_success_only
    op = operation(success: Types::Integer)

    c = op.contract
    assert_equal({}, c.params)
    assert_equal Types::Integer, c.success
    assert_equal [], c.errors
  end

  def test_errors_only
    op = operation(errors: %i[not_found forbidden])

    c = op.contract
    assert_equal({}, c.params)
    assert_nil c.success
    assert_equal %i[not_found forbidden], c.errors
  end

  def test_params_types_are_dry_types
    op = operation(params: { count: Types::Integer })

    type = op.contract.params[:count]
    assert type.respond_to?(:call), "expected a Dry::Types type"
  end

  def test_inheritance_child_inherits_parent_contract
    parent = operation(
      params: { name: Types::String },
      success: Types::String,
      errors: [:not_found]
    )
    child = build_operation(parent: parent)

    c = child.contract
    assert_equal [:name], c.params.keys
    assert_equal Types::String, c.success
    assert_equal [:not_found], c.errors
  end

  def test_inheritance_child_merges_errors
    parent = operation(errors: [:not_found])
    child = build_operation(parent: parent) do
      error :forbidden
    end

    assert_equal %i[not_found forbidden], child.contract.errors
  end

  def test_contract_is_frozen
    op = build_operation
    assert op.contract.frozen?
  end

  def test_pattern_matching
    op = operation(
      params: { id: Types::Integer },
      success: Types::Integer,
      errors: [:missing]
    )

    op.contract => { params:, success:, errors: }

    assert_equal [:id], params.keys
    assert_equal Types::Integer, success
    assert_equal [:missing], errors
  end

  def test_to_h
    op = operation(success: Types::String, errors: [:fail])

    h = op.contract.to_h
    assert_instance_of Hash, h
    assert_equal Types::String, h[:success]
    assert_equal [:fail], h[:errors]
    assert h.key?(:params)
  end
end
