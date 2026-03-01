# frozen_string_literal: true

module Dex
  class Operation
    class Pipeline
      Step = Data.define(:name, :method)

      def initialize(steps = [])
        @steps = steps.dup
      end

      def dup
        self.class.new(@steps)
      end

      def steps
        @steps.dup.freeze
      end

      def add(name, method: :"_#{name}_wrap", before: nil, after: nil, at: nil)
        _validate_positioning!(before, after, at)
        step = Step.new(name: name, method: method)

        if at == :outer then @steps.unshift(step)
        elsif at == :inner then @steps.push(step)
        elsif before then @steps.insert(_find_index!(before), step)
        elsif after then @steps.insert(_find_index!(after) + 1, step)
        else @steps.push(step)
        end
        self
      end

      def remove(name)
        @steps.reject! { |s| s.name == name }
        self
      end

      def execute(operation)
        chain = @steps.reverse_each.reduce(-> { yield }) do |next_step, step|
          -> { operation.send(step.method, &next_step) }
        end
        chain.call
      end

      private

      def _validate_positioning!(before, after, at)
        count = [before, after, at].count { |v| !v.nil? }
        raise ArgumentError, "specify only one of before:, after:, at:" if count > 1
        raise ArgumentError, "at: must be :outer or :inner" if at && !%i[outer inner].include?(at)
      end

      def _find_index!(name)
        idx = @steps.index { |s| s.name == name }
        raise ArgumentError, "pipeline step :#{name} not found" unless idx
        idx
      end
    end
  end
end
