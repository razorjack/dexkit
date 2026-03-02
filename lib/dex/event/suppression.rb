# frozen_string_literal: true

module Dex
  class Event
    module Suppression
      SUPPRESSED_KEY = :_dex_event_suppressed

      class << self
        include ExecutionState

        def suppress(*classes, &block)
          previous = _suppressed_set
          new_set = previous.dup
          if classes.empty?
            new_set << :all
          else
            classes.each do |klass|
              unless klass.is_a?(Class) && klass < Dex::Event
                raise ArgumentError, "#{klass.inspect} is not a Dex::Event subclass"
              end

              new_set << klass
            end
          end
          _set_suppressed(new_set)
          yield
        ensure
          _set_suppressed(previous)
        end

        def suppressed?(event_class)
          set = _suppressed_set
          set.include?(:all) || set.any? { |k| k != :all && event_class <= k }
        end

        def clear!
          _execution_state[SUPPRESSED_KEY] = Set.new
        end

        private

        def _suppressed_set
          _execution_state[SUPPRESSED_KEY] ||= Set.new
        end

        def _set_suppressed(set)
          _execution_state[SUPPRESSED_KEY] = set
        end
      end
    end
  end
end
