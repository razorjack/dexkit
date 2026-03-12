# frozen_string_literal: true

require "test_helper"
require "dex/operation/test_helpers"

class TestTraceAssertions < Minitest::Test
  include Dex::Operation::TestHelpers

  def test_trace_assertions_observe_current_trace
    tester = self

    op = define_operation(:TraceAssertionOp) do
      transaction false

      define_method(:perform) do
        tester.assert_trace_actor(type: :user, id: 5)
        tester.assert_trace_includes(self.class)
        tester.assert_trace_depth(2)
      end
    end

    Dex::Trace.start(actor: { type: :user, id: 5 }) do
      op.call
    end
  end
end
