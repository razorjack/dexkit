# frozen_string_literal: true

require "test_helper"

class TestEventHandlerCallbacks < Minitest::Test
  def test_before_callback_runs_before_perform
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      before { log << :before }
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[before perform], log
  end

  def test_after_callback_runs_after_perform
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      after { log << :after }
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[perform after], log
  end

  def test_around_callback_wraps_perform
    log = []
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      around ->(cont) {
        log << :around_before
        cont.call
        log << :around_after
      }
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[around_before perform around_after], log
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

  def test_callbacks_inherited_from_parent
    log = []
    event_class = build_event { prop :name, String }

    parent = build_handler do
      before { log << :parent_before }
    end

    Class.new(parent) do
      on event_class
      define_method(:perform) { log << :perform }
    end

    event_class.new(name: "test").publish(sync: true)
    assert_equal %i[parent_before perform], log
  end

  def test_child_callbacks_dont_affect_parent
    parent = build_handler do
      def perform
      end
    end

    Class.new(parent) do
      before { "child only" }
    end

    refute parent._callback_any?
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

  def test_callback_accesses_event
    received = nil
    event_class = build_event { prop :name, String }

    build_handler do
      on event_class
      before { received = event.name }
      define_method(:perform) {}
    end

    event_class.new(name: "hello").publish(sync: true)
    assert_equal "hello", received
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

  def test_call_is_private
    handler = build_handler do
      def perform; end # rubocop:disable Style/EmptyMethod,Style/SingleLineMethods
    end

    refute handler.public_method_defined?(:call)
    assert handler.private_method_defined?(:call)
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
