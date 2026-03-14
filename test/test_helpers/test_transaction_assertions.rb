# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestTransactionAssertions < Minitest::Test
  include Dex::Operation::TestHelpers
  include OperationHelpers

  def setup
    super
    setup_test_database
  end

  def test_assert_rolls_back
    op = build_operation do
      error :fail
      define_method(:perform) do
        TestModel.create!(name: "Should be rolled back")
        error!(:fail)
      end
    end
    assert_rolls_back(TestModel) { op.new.call }

    committed_op = build_operation do
      define_method(:perform) do
        TestModel.create!(name: "Persisted")
      end
    end
    assert_raises(Minitest::Assertion) do
      assert_rolls_back(TestModel) { committed_op.new.call }
    end
  end

  def test_assert_commits
    op = build_operation do
      define_method(:perform) do
        TestModel.create!(name: "Persisted")
      end
    end
    assert_commits(TestModel) { op.new.call }

    noop_op = build_operation { def perform = "no db" }
    assert_raises(Minitest::Assertion) do
      assert_commits(TestModel) { noop_op.new.call }
    end
  end
end
