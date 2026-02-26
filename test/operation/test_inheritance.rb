# frozen_string_literal: true

require "test_helper"

class TestOperationInheritance < Minitest::Test
  def setup
    setup_test_database
  end

  # Verify that wrappers apply at each level of multi-level inheritance

  def test_child_operation_is_wrapped
    # Child defines its own perform — wrappers must still apply
    op = build_operation(parent: build_operation) do
      rescue_from RuntimeError, as: :runtime_error
      def perform = raise(RuntimeError, "boom")
    end
    err = assert_raises(Dex::Error) { op.new.call }
    assert_equal :runtime_error, err.code
  end

  def test_callbacks_run_once_in_multi_level_inheritance
    log = []
    parent = build_operation do
      before_perform { log << :callback }
      def perform = nil
    end
    child = build_operation(parent: parent)
    child.new.call
    assert_equal 1, log.count(:callback), "callback should run exactly once"
  end

  def test_call_is_public
    op = build_operation { def perform = "ok" }
    assert_equal "ok", op.new.call
  end
end
