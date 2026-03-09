# frozen_string_literal: true

module Dex
  class Operation
    module TestHelpers
      def stub_operation(klass, returns: nil, error: nil, &block)
        raise ArgumentError, "stub_operation requires a block" unless block

        opts = if error
          { error: error }
        else
          { returns: returns }
        end

        Dex::Operation::TestWrapper.register_stub(klass, **opts)
        yield
      ensure
        Dex::Operation::TestWrapper.clear_stub(klass)
      end

      def spy_on_operation(klass, &block)
        spy = Spy.new(klass)
        yield spy
        spy
      end

      class Spy
        def initialize(klass)
          @klass = klass
          @started_at = Dex::TestLog.size
        end

        def calls
          Dex::TestLog.calls[@started_at..].select { |e| e.operation_class == @klass }
        end

        def called?
          calls.any?
        end

        def called_once?
          calls.size == 1
        end

        def call_count
          calls.size
        end

        def last_result
          calls.last&.result
        end

        def called_with?(**params)
          calls.any? do |entry|
            params.all? { |k, v| entry.params[k] == v }
          end
        end
      end
    end
  end
end
