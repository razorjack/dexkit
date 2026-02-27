# frozen_string_literal: true

require "test_helper"

class TestOperationSuccess < Minitest::Test
  def setup
    setup_test_database
  end

  def test_success_with_value
    op = build_operation do
      def perform
        success!(42)
      end
    end

    assert_equal 42, op.new.call
  end

  def test_success_with_kwargs
    op = build_operation do
      def perform
        success!(name: "John", age: 30)
      end
    end

    result = op.new.call
    assert_equal({ name: "John", age: 30 }, result)
  end

  def test_success_with_no_args
    op = build_operation do
      def perform
        success!
      end
    end

    assert_nil op.new.call
  end

  def test_success_short_circuits
    log = []
    op = build_operation do
      define_method(:perform) do
        log << :before
        success!("done")
        log << :after
      end
    end

    result = op.new.call
    assert_equal "done", result
    assert_equal [:before], log
  end

  def test_success_from_helper_method
    op = build_operation do
      def perform
        validate!
        "should not reach"
      end

      def validate!
        success!("early exit")
      end
    end

    assert_equal "early exit", op.new.call
  end

  def test_success_with_safe_returns_ok
    op = build_operation do
      def perform
        success!(42)
      end
    end

    outcome = op.new.safe.call
    assert outcome.ok?
    assert_equal 42, outcome.value
  end

  def test_success_inside_transaction_commits
    op = build_operation do
      def perform
        TestModel.create!(name: "Committed")
        success!("done")
      end
    end

    op.new.call
    assert_equal 1, TestModel.count
    assert_equal "Committed", TestModel.last.name
  end

  def test_success_runs_after_callbacks
    log = []
    op = build_operation do
      after { log << :after }
      define_method(:perform) do
        log << :perform
        success!("done")
      end
    end

    op.new.call
    assert_equal [:perform, :after], log
  end

  def test_success_runs_around_post_yield
    log = []
    op = build_operation do
      around do |cont|
        log << :around_pre
        cont.call
        log << :around_post
      end
      define_method(:perform) do
        log << :perform
        success!("done")
      end
    end

    op.new.call
    assert_equal [:around_pre, :perform, :around_post], log
  end

  def test_error_skips_after_callbacks
    log = []
    op = build_operation do
      after { log << :after }
      define_method(:perform) do
        log << :perform
        error!(:fail)
      end
    end

    assert_raises(Dex::Error) { op.new.call }
    assert_equal [:perform], log
  end

  def test_error_skips_around_post_yield
    log = []
    op = build_operation do
      around do |cont|
        log << :around_pre
        cont.call
        log << :around_post
      end
      define_method(:perform) do
        log << :perform
        error!(:fail)
      end
    end

    assert_raises(Dex::Error) { op.new.call }
    assert_equal [:around_pre, :perform], log
  end

  def test_error_still_rolls_back_transaction
    op = build_operation do
      def perform
        TestModel.create!(name: "Should be rolled back")
        error!(:fail, "something went wrong")
      end
    end

    assert_raises(Dex::Error) { op.new.call }
    assert_equal 0, TestModel.count
  end

  def test_error_still_works_with_safe
    op = build_operation do
      def perform
        error!(:not_found, "missing")
      end
    end

    outcome = op.new.safe.call
    assert outcome.error?
    assert_equal :not_found, outcome.code
  end
end
