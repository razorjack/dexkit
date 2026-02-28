# frozen_string_literal: true

require "test_helper"
require "dex/test_helpers"

class TestStubbing < Minitest::Test
  include Dex::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_stub_operation_with_return_value
    op = build_operation { def perform = "real" }

    stub_operation(op, returns: "fake") do
      assert_equal "fake", op.new.call
    end

    assert_equal "real", op.new.call
  end

  def test_stub_operation_with_nil_return
    op = build_operation { def perform = "real" }

    stub_operation(op, returns: nil) do
      assert_nil op.new.call
    end
  end

  def test_stub_operation_with_error_symbol
    op = build_operation { def perform = "real" }

    stub_operation(op, error: :fake_error) do
      err = assert_raises(Dex::Error) { op.new.call }
      assert_equal :fake_error, err.code
    end
  end

  def test_stub_operation_with_error_hash
    op = build_operation { def perform = "real" }

    stub_operation(op, error: { code: :fail, message: "custom msg" }) do
      err = assert_raises(Dex::Error) { op.new.call }
      assert_equal :fail, err.code
      assert_equal "custom msg", err.message
    end
  end

  def test_stub_clears_after_block
    op = build_operation { def perform = "real" }

    stub_operation(op, returns: "fake") do
      assert_equal "fake", op.new.call
    end

    assert_equal "real", op.new.call
  end

  def test_stub_clears_on_exception
    op = build_operation { def perform = "real" }

    begin
      stub_operation(op, returns: "fake") do
        raise "boom"
      end
    rescue RuntimeError
      nil
    end

    assert_equal "real", op.new.call
  end

  def test_stub_works_with_safe
    op = build_operation { def perform = "real" }

    stub_operation(op, error: :stubbed) do
      result = op.new.safe.call
      assert result.error?
      assert_equal :stubbed, result.code
    end
  end

  def test_stub_bypasses_perform
    performed = false
    op = build_operation do
      define_method(:perform) {
        performed = true
        "real"
      }
    end

    stub_operation(op, returns: "fake") do
      op.new.call
    end

    refute performed
  end

  def test_stub_does_not_record_to_test_log
    op = build_operation { def perform = "real" }
    Dex::TestLog.clear!

    stub_operation(op, returns: "fake") do
      op.new.call
    end

    assert Dex::TestLog.empty?
  end

  def test_stub_requires_block
    op = build_operation { def perform = "real" }
    assert_raises(ArgumentError) { stub_operation(op, returns: "fake") }
  end
end
