# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestTestLog < Minitest::Test
  include Dex::Operation::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_starts_empty
    assert Dex::TestLog.empty?
    assert_equal 0, Dex::TestLog.size
  end

  def test_records_operation_call
    op = build_operation { def perform = "hello" }
    op.new.call

    assert_equal 1, Dex::TestLog.size
    refute Dex::TestLog.empty?
  end

  def test_entry_contains_operation_info
    op = build_operation { def perform = 42 }
    op.new.call

    entry = Dex::TestLog.calls.first
    assert_equal "Operation", entry.type
    assert_equal op, entry.operation_class
    assert entry.result.ok?
    assert_equal 42, entry.result.value
    assert_kind_of Float, entry.duration
  end

  def test_entry_contains_params
    op = build_operation do
      prop :name, String
      def perform = name
    end
    op.new(name: "Alice").call

    entry = Dex::TestLog.calls.first
    assert_equal({ name: "Alice" }, entry.params)
  end

  def test_records_errors
    op = build_operation do
      error :boom
      def perform = error!(:boom, "it broke")
    end

    begin
      op.new.call
    rescue Dex::Error
      nil
    end

    entry = Dex::TestLog.calls.first
    assert entry.result.error?
    assert_equal :boom, entry.result.code
  end

  def test_clear_resets_log
    op = build_operation { def perform = nil }
    op.new.call
    assert_equal 1, Dex::TestLog.size

    Dex::TestLog.clear!
    assert Dex::TestLog.empty?
  end

  def test_calls_returns_duplicate
    op = build_operation { def perform = nil }
    op.new.call

    calls = Dex::TestLog.calls
    calls.clear
    assert_equal 1, Dex::TestLog.size
  end

  def test_find_by_class
    op_a = build_operation { def perform = "a" }
    op_b = build_operation { def perform = "b" }

    op_a.new.call
    op_b.new.call
    op_a.new.call

    found = Dex::TestLog.find(op_a)
    assert_equal 2, found.size
    found.each { |e| assert_equal op_a, e.operation_class }
  end

  def test_find_by_class_and_params
    op = build_operation do
      prop :name, String
      def perform = name
    end

    op.new(name: "Alice").call
    op.new(name: "Bob").call

    found = Dex::TestLog.find(op, name: "Bob")
    assert_equal 1, found.size
    assert_equal({ name: "Bob" }, found.first.params)
  end

  def test_summary_when_empty
    assert_equal "No operations called.", Dex::TestLog.summary
  end

  def test_summary_with_entries
    op = build_operation { def perform = "ok" }
    op.new.call

    summary = Dex::TestLog.summary
    assert_match(/Operations called \(1\)/, summary)
    assert_match(/OK/, summary)
  end

  def test_summary_with_errors
    op = build_operation do
      error :fail
      def perform = error!(:fail)
    end

    begin
      op.new.call
    rescue Dex::Error
      nil
    end

    summary = Dex::TestLog.summary
    assert_match(/ERR\(fail\)/, summary)
  end

  def test_records_non_dex_exceptions_as_err
    op = build_operation do
      define_method(:perform) { raise "boom" }
    end

    begin
      op.new.call
    rescue RuntimeError
      nil
    end

    entry = Dex::TestLog.calls.first
    assert entry.result.error?
    assert_equal :exception, entry.result.code
    assert_equal "boom", entry.result.message
    assert_equal "RuntimeError", entry.result.details[:exception_class]
  end
end
