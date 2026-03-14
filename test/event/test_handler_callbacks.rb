# frozen_string_literal: true

require "test_helper"

class TestEventHandlerCallbacks < Minitest::Test
  def test_callback_execution_order
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      before { log << :before }
      around ->(cont) {
        log << :around_before
        cont.call
        log << :around_after
      }
      after { log << :after }
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[around_before before perform after around_after], log
  end

  def test_multiple_callbacks_in_order
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      before { log << :first }
      before { log << :second }
      after { log << :done }
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[first second perform done], log
  end

  def test_callback_inheritance
    log = []
    event_class = build_event { prop :name, String }

    parent = build_handler do
      before { log << :parent_before }
    end

    # Child inherits parent callbacks
    Class.new(parent) do
      on event_class
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[parent_before perform], log

    # Child callbacks don't affect parent
    another_parent = build_handler { def perform = nil }
    Class.new(another_parent) { before { "child only" } }
    refute another_parent._callback_any?
  end

  def test_callback_with_symbol_method
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      before :setup_stuff

      define_method(:setup_stuff) { log << :setup }
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[setup perform], log
  end

  def test_use_adds_custom_wrapper_to_handler
    log = []
    event_class = build_event { prop :name, String }

    wrapper = Module.new do
      define_method(:_custom_wrap) do |&block|
        log << :wrapped
        block.call
      end
    end

    build_handler do
      on event_class
      use wrapper, as: :custom
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[wrapped perform], log
  end

  def test_handler_pipeline_default_steps
    steps = Dex::Event::Handler.pipeline.steps.map(&:name)
    assert_equal %i[transaction callback], steps
  end

  def test_defining_call_on_handler_raises
    err = assert_raises(ArgumentError) do
      build_handler do
        def call
        end
      end
    end
    assert_match(/must not define #call/, err.message)
  end
end
