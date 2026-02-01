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
      op.async.perform
    end
  end

  def test_job_executes_operation
    spy = Minitest::Mock.new
    spy.expect :call, nil, ["Test"]

    define_operation(:TestSpyOperation) do
      params do
        attribute :name, Types::String
        attribute :spy, Types::Any
      end

      def perform
        params.spy.call(params.name)
      end
    end

    # Directly test the job execution (avoids Rails 8 tagged_logger issues)
    Dex::Operation::Job.new.perform(class_name: "TestSpyOperation", params: { name: "Test", spy: spy })

    assert_mock spy
  end

  def test_async_with_queue
    op = build_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job, queue: "low") do
      op.async(queue: "low").perform
    end
  end

  def test_async_with_delay
    freeze_time = Time.now
    Time.stub :now, freeze_time do
      op = build_operation.new(name: "Test")

      assert_enqueued_with(job: Dex::Operation::Job) do
        op.async(in: 300).perform # 5 minutes in seconds
      end
    end
  end

  def test_async_with_scheduled_time
    scheduled_time = Time.now + 3600 # 1 hour from now
    op = build_operation.new(name: "Test")

    assert_enqueued_with(job: Dex::Operation::Job, at: scheduled_time) do
      op.async(at: scheduled_time).perform
    end
  end

  def test_class_level_async_sets_defaults
    op_class = Class.new(Dex::Operation) do
      async queue: "background"

      params do
        attribute :name, Types::String
      end

      def perform; end
    end

    assert_enqueued_with(job: Dex::Operation::Job, queue: "background") do
      op_class.new(name: "Test").async.perform
    end
  end

  def test_runtime_options_override_class_defaults
    op_class = Class.new(Dex::Operation) do
      async queue: "low"

      params do
        attribute :name, Types::String
      end

      def perform; end
    end

    assert_enqueued_with(job: Dex::Operation::Job, queue: "urgent") do
      op_class.new(name: "Test").async(queue: "urgent").perform
    end
  end

  def test_set_async_equivalent_to_shortcut
    op1 = Class.new(Dex::Operation) do
      async queue: "low"
    end

    op2 = Class.new(Dex::Operation) do
      set :async, queue: "low"
    end

    assert_equal op1.settings_for(:async), op2.settings_for(:async)
  end

  def test_settings_inheritance_for_async
    parent = Class.new(Dex::Operation) do
      async queue: "default", priority: 5
    end

    child = Class.new(parent) do
      async priority: 10
    end

    assert_equal({ queue: "default", priority: 10 }, child.settings_for(:async))
  end

  private

  # Override the global helper with test-specific defaults
  def build_operation
    super do
      params do
        attribute :name, Types::String
      end

      def perform; end
    end
  end
end
