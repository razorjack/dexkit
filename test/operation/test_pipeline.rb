# frozen_string_literal: true

require "test_helper"

class TestOperationPipeline < Minitest::Test
  def setup
    setup_test_database
  end

  # --- Pipeline class ---

  def test_default_pipeline_step_order
    names = Dex::Operation.pipeline.steps.map(&:name)
    assert_equal %i[result lock transaction record rescue callback], names
  end

  def test_pipeline_steps_returns_frozen_list
    steps = Dex::Operation.pipeline.steps
    assert steps.frozen?
  end

  def test_pipeline_add_with_before
    pipeline = Dex::Pipeline.new
    pipeline.add(:a)
    pipeline.add(:b)
    pipeline.add(:c, before: :b)
    assert_equal %i[a c b], pipeline.steps.map(&:name)
  end

  def test_pipeline_add_with_after
    pipeline = Dex::Pipeline.new
    pipeline.add(:a)
    pipeline.add(:b)
    pipeline.add(:c, after: :a)
    assert_equal %i[a c b], pipeline.steps.map(&:name)
  end

  def test_pipeline_add_at_outer
    pipeline = Dex::Pipeline.new
    pipeline.add(:a)
    pipeline.add(:b, at: :outer)
    assert_equal %i[b a], pipeline.steps.map(&:name)
  end

  def test_pipeline_add_at_inner
    pipeline = Dex::Pipeline.new
    pipeline.add(:a)
    pipeline.add(:b, at: :inner)
    assert_equal %i[a b], pipeline.steps.map(&:name)
  end

  def test_pipeline_remove
    pipeline = Dex::Pipeline.new
    pipeline.add(:a)
    pipeline.add(:b)
    pipeline.add(:c)
    pipeline.remove(:b)
    assert_equal %i[a c], pipeline.steps.map(&:name)
  end

  def test_pipeline_error_unknown_step_in_before
    pipeline = Dex::Pipeline.new
    pipeline.add(:a)
    err = assert_raises(ArgumentError) { pipeline.add(:b, before: :z) }
    assert_match(/pipeline step :z not found/, err.message)
  end

  def test_pipeline_error_unknown_step_in_after
    pipeline = Dex::Pipeline.new
    pipeline.add(:a)
    err = assert_raises(ArgumentError) { pipeline.add(:b, after: :z) }
    assert_match(/pipeline step :z not found/, err.message)
  end

  def test_pipeline_error_multiple_positioning_args
    pipeline = Dex::Pipeline.new
    pipeline.add(:a)
    err = assert_raises(ArgumentError) { pipeline.add(:b, before: :a, after: :a) }
    assert_match(/specify only one/, err.message)
  end

  def test_pipeline_error_invalid_at_value
    pipeline = Dex::Pipeline.new
    err = assert_raises(ArgumentError) { pipeline.add(:a, at: :middle) }
    assert_match(/at: must be :outer or :inner/, err.message)
  end

  def test_pipeline_dup_returns_independent_copy
    original = Dex::Pipeline.new
    original.add(:a)
    copy = original.dup
    copy.add(:b)
    assert_equal %i[a], original.steps.map(&:name)
    assert_equal %i[a b], copy.steps.map(&:name)
  end

  # --- Pipeline inheritance ---

  def test_child_gets_independent_pipeline_copy
    parent = build_operation
    child = build_operation(parent: parent)

    parent_steps = parent.pipeline.steps.map(&:name)
    child_steps = child.pipeline.steps.map(&:name)
    assert_equal parent_steps, child_steps
    refute_same parent.pipeline, child.pipeline
  end

  # --- use DSL ---

  def test_use_adds_custom_wrapper
    log = []
    wrapper = Module.new do
      define_method(:_custom_wrap) do |&block|
        log << :before
        result = block.call
        log << :after
        result
      end
    end

    op = build_operation do
      use wrapper, as: :custom
      def perform = "done"
    end

    result = op.new.call
    assert_equal "done", result
    assert_equal %i[before after], log
  end

  def test_use_with_as_and_wrap_overrides
    log = []
    wrapper = Module.new do
      define_method(:_my_method) do |&block|
        log << :wrapped
        block.call
      end
    end

    op = build_operation do
      use wrapper, as: :custom, wrap: :_my_method
      def perform = "ok"
    end

    result = op.new.call
    assert_equal "ok", result
    assert_equal [:wrapped], log
  end

  def test_use_with_before_positioning
    log = []
    wrapper = Module.new do
      define_method(:_audit_wrap) do |&block|
        log << :audit
        block.call
      end
    end

    op = Class.new(Dex::Operation) do
      use wrapper, as: :audit, before: :callback
      define_method(:perform) do
        log << :perform
        "ok"
      end
    end

    op.new.call
    assert_equal %i[audit perform], log
  end

  def test_use_derives_step_name_from_module
    wrapper = Module.new
    # Anonymous modules need explicit as:
    err = assert_raises(ArgumentError) do
      build_operation { use wrapper }
    end
    assert_match(/anonymous modules require explicit as:/, err.message)
  end

  def test_use_on_subclass_does_not_affect_parent
    parent = build_operation { def perform = "parent" }
    parent_step_count = parent.pipeline.steps.size

    log = []
    wrapper = Module.new do
      define_method(:_extra_wrap) do |&block|
        log << :extra
        block.call
      end
    end

    child = build_operation(parent: parent) do
      use wrapper, as: :extra
      def perform = "child"
    end

    assert_equal parent_step_count, parent.pipeline.steps.size
    assert_equal parent_step_count + 1, child.pipeline.steps.size

    child.new.call
    assert_equal [:extra], log
  end

  def test_use_with_bad_before_does_not_include_module
    wrapper = Module.new do
      def _leaked_wrap(&block) = block.call
    end

    op = build_operation
    assert_raises(ArgumentError) do
      op.use wrapper, as: :leaked, before: :nonexistent
    end

    refute op.ancestors.include?(wrapper)
  end

  def test_parent_use_after_child_creation_does_not_affect_child
    parent = build_operation
    child = build_operation(parent: parent)

    child_steps_before = child.pipeline.steps.map(&:name)

    wrapper = Module.new do
      def _late_wrap(&block) = block.call
    end
    parent.use wrapper, as: :late

    assert_includes parent.pipeline.steps.map(&:name), :late
    assert_equal child_steps_before, child.pipeline.steps.map(&:name)
  end

  # --- Pipeline execute ---

  def test_pipeline_executes_in_correct_order
    log = []
    pipeline = Dex::Pipeline.new

    wrapper_mod = Module.new do
      define_method(:_outer_wrap) do |&block|
        log << :outer_start
        result = block.call
        log << :outer_end
        result
      end

      define_method(:_inner_wrap) do |&block|
        log << :inner_start
        result = block.call
        log << :inner_end
        result
      end
    end

    op = build_operation do
      include wrapper_mod

      def perform = "done"
    end

    pipeline.add(:outer)
    pipeline.add(:inner)

    pipeline.execute(op.new) { op.new.send(:perform) }
    assert_equal %i[outer_start inner_start inner_end outer_end], log
  end
end
