# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestSpying < Minitest::Test
  include Dex::Operation::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_spy_tracks_calls
    op = build_operation { def perform = "ok" }

    spy_on_operation(op) do |spy|
      op.new.call
      assert spy.called?
      assert spy.called_once?
      assert_equal 1, spy.call_count
    end
  end

  def test_spy_tracks_multiple_calls
    op = build_operation { def perform = "ok" }

    spy_on_operation(op) do |spy|
      op.new.call
      op.new.call
      assert_equal 2, spy.call_count
      refute spy.called_once?
    end
  end

  def test_spy_not_called
    op = build_operation { def perform = "ok" }

    spy_on_operation(op) do |spy|
      refute spy.called?
      assert_equal 0, spy.call_count
    end
  end

  def test_spy_last_result
    op = build_operation { def perform = 42 }

    spy_on_operation(op) do |spy|
      op.new.call
      assert spy.last_result.ok?
      assert_equal 42, spy.last_result.value
    end
  end

  def test_spy_last_result_error
    op = build_operation do
      error :fail
      def perform = error!(:fail)
    end

    spy_on_operation(op) do |spy|
      begin
        op.new.call
      rescue Dex::Error
        nil
      end
      assert spy.last_result.error?
      assert_equal :fail, spy.last_result.code
    end
  end

  def test_spy_called_with
    op = build_operation do
      prop :name, String
      def perform = name
    end

    spy_on_operation(op) do |spy|
      op.new(name: "Alice").call
      op.new(name: "Bob").call

      assert spy.called_with?(name: "Alice")
      assert spy.called_with?(name: "Bob")
      refute spy.called_with?(name: "Charlie")
    end
  end

  def test_spy_only_sees_its_own_class
    op_a = build_operation { def perform = "a" }
    op_b = build_operation { def perform = "b" }

    spy_on_operation(op_a) do |spy|
      op_a.new.call
      op_b.new.call

      assert_equal 1, spy.call_count
    end
  end

  def test_spy_only_sees_calls_after_creation
    op = build_operation { def perform = "ok" }
    op.new.call

    spy_on_operation(op) do |spy|
      refute spy.called?
      op.new.call
      assert spy.called_once?
    end
  end

  def test_spy_real_execution_happens
    log = []
    op = build_operation do
      define_method(:perform) {
        log << :performed
        "done"
      }
    end

    spy_on_operation(op) do |spy|
      op.new.call
      assert spy.called?
    end

    assert_equal [:performed], log
  end

  def test_spy_sees_non_dex_exceptions_as_err
    op = build_operation do
      define_method(:perform) { raise "kaboom" }
    end

    spy_on_operation(op) do |spy|
      begin
        op.new.call
      rescue RuntimeError
        nil
      end

      assert spy.called?
      assert spy.last_result.error?
      assert_equal :exception, spy.last_result.code
    end
  end
end
