# frozen_string_literal: true

require "test_helper"

class TestOperationError < Minitest::Test
  def setup
    setup_test_database
  end

  def test_error_raises_dex_error
    op = Class.new(Dex::Operation) do
      def perform
        error!(:invalid_input, "Name cannot be blank")
      end
    end

    err = assert_raises(Dex::Error) do
      op.new.perform
    end

    assert_equal :invalid_input, err.code
    assert_equal "Name cannot be blank", err.message
  end

  def test_error_with_code_only
    op = Class.new(Dex::Operation) do
      def perform
        error!(:not_found)
      end
    end

    err = assert_raises(Dex::Error) do
      op.new.perform
    end

    assert_equal :not_found, err.code
    assert_equal "not_found", err.message
  end

  def test_error_with_details
    op = Class.new(Dex::Operation) do
      def perform
        error!(:validation_failed, "Invalid data", details: {field: "email", issue: "format"})
      end
    end

    err = assert_raises(Dex::Error) do
      op.new.perform
    end

    assert_equal :validation_failed, err.code
    assert_equal "Invalid data", err.message
    assert_equal({field: "email", issue: "format"}, err.details)
  end

  def test_error_deconstruct_keys
    error = Dex::Error.new(:duplicate, "Record already exists", details: {id: 123})

    case error
    in {code: :duplicate, message:, details:}
      assert_equal "Record already exists", message
      assert_equal({id: 123}, details)
    else
      flunk "Pattern matching failed"
    end
  end
end
