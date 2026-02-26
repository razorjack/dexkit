# frozen_string_literal: true

require "test_helper"

class TestOperationCallbacks < Minitest::Test
  def setup
    setup_test_database
  end

  # before

  def test_before_symbol
    log = []
    op = build_operation do
      before :setup_step
      define_method(:setup_step) { log << :setup }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:setup, :perform], log
  end

  def test_before_lambda
    log = []
    callable = -> { log << :before }
    op = build_operation do
      before callable
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:before, :perform], log
  end

  def test_before_block
    log = []
    op = build_operation do
      before { log << :before }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:before, :perform], log
  end

  def test_before_multiple_in_order
    log = []
    op = build_operation do
      before { log << :first }
      before { log << :second }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:first, :second, :perform], log
  end

  def test_before_accesses_params
    op = build_operation do
      params { attribute :name, Types::String }
      before { error!(:invalid) if name == "bad" }
      def perform = "ok"
    end
    assert_raises(Dex::Error) { op.new(name: "bad").call }
    assert_equal "ok", op.new(name: "good").call
  end

  def test_before_error_prevents_perform
    log = []
    op = build_operation do
      before { error!(:stopped) }
      define_method(:perform) { log << :performed }
    end
    assert_raises(Dex::Error) { op.new.call }
    assert_empty log
  end

  # after

  def test_after_symbol
    log = []
    op = build_operation do
      after :finish_step
      define_method(:finish_step) { log << :finish }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:perform, :finish], log
  end

  def test_after_lambda
    log = []
    callable = -> { log << :after }
    op = build_operation do
      after callable
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:perform, :after], log
  end

  def test_after_block
    log = []
    op = build_operation do
      after { log << :after }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:perform, :after], log
  end

  def test_after_multiple_in_order
    log = []
    op = build_operation do
      after { log << :first }
      after { log << :second }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:perform, :first, :second], log
  end

  def test_after_skipped_on_error
    log = []
    op = build_operation do
      after { log << :after }
      define_method(:perform) { raise "boom" }
    end
    assert_raises(RuntimeError) { op.new.call }
    assert_empty log
  end

  # around

  def test_around_symbol
    log = []
    op = build_operation do
      around :wrap_step
      define_method(:wrap_step) { |&blk|
        log << :before
        blk.call
        log << :after
      }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:before, :perform, :after], log
  end

  def test_around_lambda
    log = []
    callable = ->(cont) {
      log << :before
      cont.call
      log << :after
    }
    op = build_operation do
      around callable
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:before, :perform, :after], log
  end

  def test_around_multiple_nest
    log = []
    op = build_operation do
      around { |c|
        log << :outer_start
        c.call
        log << :outer_end
      }
      around { |c|
        log << :inner_start
        c.call
        log << :inner_end
      }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:outer_start, :inner_start, :perform, :inner_end, :outer_end], log
  end

  def test_around_no_yield_skips_perform
    log = []
    op = build_operation do
      around { |_cont| log << :short_circuit }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:short_circuit], log
  end

  # Inheritance

  def test_child_inherits_parent_callbacks
    log = []
    parent = build_operation do
      before { log << :parent }
      define_method(:perform) { log << :perform }
    end
    child = build_operation(parent: parent) do
      before { log << :child }
    end
    child.new.call
    assert_equal [:parent, :child, :perform], log
  end

  def test_parent_unaffected_by_child_callbacks
    log = []
    parent = build_operation do
      before { log << :parent }
      define_method(:perform) { log << :perform }
    end
    child = build_operation(parent: parent) do
      before { log << :child }
    end
    parent.new.call
    assert_equal [:parent, :perform], log
    child.new.call
    assert_equal [:parent, :perform, :parent, :child, :perform], log
  end

  # Combined lifecycle

  def test_full_lifecycle_order
    log = []
    op = build_operation do
      before { log << :before1 }
      before { log << :before2 }
      around { |c|
        log << :around_start
        c.call
        log << :around_end
      }
      after { log << :after1 }
      after { log << :after2 }
      define_method(:perform) { log << :perform }
    end
    op.new.call
    assert_equal [:around_start, :before1, :before2, :perform, :after1, :after2, :around_end], log
  end

  # Integration

  def test_before_error_triggers_rollback
    op = build_operation do
      before { error!(:aborted) }
      define_method(:perform) { TestModel.create!(name: "Should not exist") }
    end
    assert_raises(Dex::Error) { op.new.call }
    assert_equal 0, TestModel.count
  end

  def test_works_with_safe
    op = build_operation do
      before { error!(:stopped) }
      def perform = "ok"
    end
    result = op.new.safe.call
    assert result.error?
    assert_equal :stopped, result.code
  end
end
