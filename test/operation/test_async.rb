# frozen_string_literal: true

require "test_helper"

class TestOperationAsync < Minitest::Test
  include ActiveJob::TestHelper

  def setup
    setup_test_database
  end

  def test_async_returns_proxy
    op = build_operation.new(name: "Test")
    proxy = op.async

    assert_instance_of Dex::Operation::AsyncProxy, proxy
  end

  def test_async_perform_enqueues_job
    op = build_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job) do
      op.async.call
    end
  end

  def test_job_executes_operation
    spy = Minitest::Mock.new
    spy.expect :call, nil, ["Test"]

    operation(name: :TestSpyOperation, params: { name: Types::String, spy: Types::Any }) do
      spy.call(name)
    end

    # Directly test the job execution (avoids Rails 8 tagged_logger issues)
    Dex::Operation::Job.new.perform(class_name: "TestSpyOperation", params: { name: "Test", spy: spy })

    assert_mock spy
  end

  def test_async_with_queue
    op = build_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job, queue: "low") do
      op.async(queue: "low").call
    end
  end

  def test_async_with_delay
    freeze_time = Time.now
    Time.stub :now, freeze_time do
      op = build_operation.new(name: "Test")

      assert_enqueued_with(job: Dex::Operation::Job) do
        op.async(in: 300).call # 5 minutes in seconds
      end
    end
  end

  def test_async_with_scheduled_time
    scheduled_time = Time.now + 3600 # 1 hour from now
    op = build_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job, at: scheduled_time) do
      op.async(at: scheduled_time).call
    end
  end

  def test_class_level_async_sets_defaults
    op_class = build_operation do
      async queue: "background"
    end

    assert_enqueued_with(job: Dex::Operation::Job, queue: "background") do
      op_class.new(name: "Test").async.call
    end
  end

  def test_runtime_options_override_class_defaults
    op_class = build_operation do
      async queue: "low"
    end

    assert_enqueued_with(job: Dex::Operation::Job, queue: "urgent") do
      op_class.new(name: "Test").async(queue: "urgent").call
    end
  end

  def test_set_async_equivalent_to_shortcut
    op1 = build_operation do
      async queue: "low"
    end

    op2 = build_operation do
      set :async, queue: "low"
    end

    assert_equal op1.settings_for(:async), op2.settings_for(:async)
  end

  def test_settings_inheritance_for_async
    parent = build_operation do
      async queue: "default", priority: 5
    end

    child = build_operation(parent: parent) do
      async priority: 10
    end

    assert_equal({ queue: "default", priority: 10 }, child.settings_for(:async))
  end

  private

  # Override the global helper with test-specific defaults
  def build_operation(parent: Dex::Operation, &block)
    super do
      params do
        attribute :name, Types::String
      end

      class_eval(&block) if block

      unless method_defined?(:perform, false)
        def perform
        end
      end
    end
  end
end
