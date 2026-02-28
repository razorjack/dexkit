# frozen_string_literal: true

require "test_helper"

# Mock the gem's exception class (gem not loaded in tests)
module WithAdvisoryLock
  class FailedToAcquireLock < StandardError; end
end

class TestOperationAdvisoryLock < Minitest::Test
  def setup
    setup_test_database
  end

  def test_disabled_by_default
    op = build_operation do
      def perform = "no lock"
    end
    assert_equal "no lock", op.new.call
  end

  def test_static_string_key
    key, opts = nil
    op = build_operation do
      advisory_lock "payments"
      def perform = "locked"
    end
    stub_advisory_lock(capture_key: ->(k) { key = k }, capture_opts: ->(o) { opts = o }) do
      assert_equal "locked", op.new.call
    end
    assert_equal "payments", key
    assert_equal({}, opts)
  end

  def test_dynamic_block_key_with_param_access
    key = nil
    op = build_operation do
      prop :charge_id, String
      advisory_lock { "pay:#{charge_id}" }
      def perform = "charged"
    end
    stub_advisory_lock(capture_key: ->(k) { key = k }) do
      assert_equal "charged", op.new(charge_id: "ch_123").call
    end
    assert_equal "pay:ch_123", key
  end

  def test_symbol_key_calls_instance_method
    key = nil
    op = build_operation do
      prop :id, Integer
      advisory_lock :compute_lock_key
      define_method(:compute_lock_key) { "item:#{id}" }
      def perform = "done"
    end
    stub_advisory_lock(capture_key: ->(k) { key = k }) do
      assert_equal "done", op.new(id: 42).call
    end
    assert_equal "item:42", key
  end

  def test_class_name_key_when_no_arguments
    key = nil
    op = define_operation(:TestLockClassNameOp) do
      advisory_lock
      def perform = "ok"
    end
    stub_advisory_lock(capture_key: ->(k) { key = k }) do
      op.new.call
    end
    assert_equal "TestLockClassNameOp", key
  end

  def test_timeout_passed_as_timeout_seconds
    opts = nil
    op = build_operation do
      advisory_lock "report", timeout: 5
      def perform = "done"
    end
    stub_advisory_lock(capture_opts: ->(o) { opts = o }) do
      op.new.call
    end
    assert_equal({ timeout_seconds: 5 }, opts)
  end

  def test_no_timeout_omits_timeout_seconds
    opts = nil
    op = build_operation do
      advisory_lock "report"
      def perform = "done"
    end
    stub_advisory_lock(capture_opts: ->(o) { opts = o }) do
      op.new.call
    end
    assert_equal({}, opts)
  end

  def test_lock_failure_raises_dex_error
    op = build_operation do
      advisory_lock "contested"
      def perform = "never"
    end
    stub_advisory_lock(fail: true) do
      err = assert_raises(Dex::Error) { op.new.call }
      assert_equal :lock_timeout, err.code
      assert_match(/contested/, err.message)
    end
  end

  def test_lock_failure_with_safe_returns_err
    op = build_operation do
      advisory_lock "contested"
      def perform = "never"
    end
    stub_advisory_lock(fail: true) do
      result = op.new.safe.call
      assert result.error?
      assert_equal :lock_timeout, result.code
    end
  end

  def test_settings_inheritance_from_parent
    key = nil
    parent = build_operation do
      advisory_lock "parent-lock"
    end
    child = build_operation(parent: parent) do
      def perform = "inherited"
    end
    stub_advisory_lock(capture_key: ->(k) { key = k }) do
      assert_equal "inherited", child.new.call
    end
    assert_equal "parent-lock", key
  end

  def test_child_overrides_parent_lock
    key = nil
    parent = build_operation do
      advisory_lock "parent-lock"
    end
    child = build_operation(parent: parent) do
      advisory_lock "child-lock"
      def perform = "overridden"
    end
    stub_advisory_lock(capture_key: ->(k) { key = k }) do
      assert_equal "overridden", child.new.call
    end
    assert_equal "child-lock", key
  end

  def test_load_error_when_gem_not_available
    op = build_operation do
      advisory_lock "missing-gem"
      def perform = "never"
    end
    err = assert_raises(LoadError) { op.new.call }
    assert_match(/with_advisory_lock/, err.message)
  end

  def test_return_value_passes_through_lock
    op = build_operation do
      advisory_lock "pass-through"
      def perform = { status: "ok", count: 42 }
    end
    stub_advisory_lock do
      result = op.new.call
      assert_equal({ status: "ok", count: 42 }, result)
    end
  end

  private

  def stub_advisory_lock(fail: false, capture_key: nil, capture_opts: nil, &block)
    impl = lambda { |key, **opts, &blk|
      capture_key&.call(key)
      capture_opts&.call(opts)
      raise WithAdvisoryLock::FailedToAcquireLock if fail

      blk.call
    }

    ActiveRecord::Base.define_singleton_method(:with_advisory_lock!, impl)
    block.call
  ensure
    ActiveRecord::Base.singleton_class.remove_method(:with_advisory_lock!) if ActiveRecord::Base.respond_to?(:with_advisory_lock!)
  end
end
