# frozen_string_literal: true

require "test_helper"

class TestOperationProps < Minitest::Test
  def setup
    setup_test_database
  end

  def test_props_are_accessible_as_reader_methods
    op = operation(params: { name: String, count: Integer }) do
      "#{name}-#{count}"
    end

    assert_equal "test-3", op.new(name: "test", count: 3).call
  end

  def test_props_available_in_callbacks
    log = []
    op = build_operation do
      prop :name, String
      before { log << name }
      def perform = "done"
    end

    op.new(name: "Alice").call
    assert_equal ["Alice"], log
  end

  def test_child_inherits_props
    parent = build_operation do
      prop :name, String
      def perform = name
    end
    child = build_operation(parent: parent)

    assert_equal "inherited", child.new(name: "inherited").call
  end

  def test_reserved_prop_name_raises
    error = assert_raises(ArgumentError) do
      build_operation do
        prop :call, String
      end
    end

    assert_includes error.message, ":call"
    assert_includes error.message, "conflicts with core Operation methods"
  end

  def test_reserved_perform_name_raises
    error = assert_raises(ArgumentError) do
      build_operation do
        prop :perform, String
      end
    end

    assert_includes error.message, ":perform"
  end
end
