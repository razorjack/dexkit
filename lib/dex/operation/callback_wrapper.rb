# frozen_string_literal: true

module Dex
  module CallbackWrapper
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def before(callable = nil, &block)
        _callback_validate!(callable, block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:before) << entry
      end

      def after(callable = nil, &block)
        _callback_validate!(callable, block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:after) << entry
      end

      def around(callable = nil, &block)
        _callback_validate!(callable, block)
        entry = callable.is_a?(Symbol) ? [:method, callable] : [:proc, callable || block]
        _callback_own(:around) << entry
      end

      def _callback_list(type)
        parent_callbacks = superclass.respond_to?(:_callback_list) ? superclass._callback_list(type) : []
        parent_callbacks + _callback_own(type)
      end

      def _callback_any?
        %i[before after around].any? { |type| _callback_list(type).any? }
      end

      private

      def _callback_validate!(callable, block)
        return if callable.is_a?(Symbol)
        return if callable.nil? && block
        return if callable.is_a?(Proc)

        if callable.nil?
          raise ArgumentError, "callback requires a Symbol, Proc, or block"
        else
          raise ArgumentError, "callback must be a Symbol or Proc, got: #{callable.class}"
        end
      end

      def _callback_own(type)
        @_callbacks ||= { before: [], after: [], around: [] }
        @_callbacks[type]
      end
    end

    def _callback_wrap
      return yield unless self.class._callback_any?

      halted = nil
      result = _callback_run_around(self.class._callback_list(:around)) do
        _callback_run_before
        caught = catch(:_dex_halt) { yield }
        if caught.is_a?(Operation::Halt)
          if caught.success?
            halted = caught
            _callback_run_after
            caught.value
          else
            throw(:_dex_halt, caught)
          end
        else
          _callback_run_after
          caught
        end
      end
      throw(:_dex_halt, halted) if halted
      result
    end

    private

    def _callback_run_before
      self.class._callback_list(:before).each { |cb| _callback_invoke(cb) }
    end

    def _callback_run_after
      self.class._callback_list(:after).each { |cb| _callback_invoke(cb) }
    end

    def _callback_invoke(cb)
      kind, callable = cb
      case kind
      when :method then send(callable)
      when :proc then instance_exec(&callable)
      end
    end

    def _callback_run_around(chain, &core)
      if chain.empty?
        core.call
      else
        kind, callable = chain.first
        rest = chain[1..]
        continuation = -> { _callback_run_around(rest, &core) }
        case kind
        when :method then send(callable) { continuation.call }
        when :proc then instance_exec(continuation, &callable)
        end
      end
    end
  end
end
