# frozen_string_literal: true

module Dex
  module GuardWrapper
    extend Dex::Concern

    GuardDefinition = Data.define(:name, :message, :requires, :block)

    module ClassMethods
      def guard(code, message = nil, requires: nil, &block)
        raise ArgumentError, "guard code must be a Symbol, got: #{code.inspect}" unless code.is_a?(Symbol)
        raise ArgumentError, "guard requires a block" unless block

        requires = _guard_normalize_requires!(code, requires)
        _guard_validate_unique!(code)

        _guard_own << GuardDefinition.new(name: code, message: message, requires: requires, block: block)

        error(code) if respond_to?(:error)
      end

      def _guard_list
        parent = superclass.respond_to?(:_guard_list) ? superclass._guard_list : []
        parent + _guard_own
      end

      def callable(**kwargs)
        instance = new(**kwargs)
        failures = instance.send(:_guard_evaluate)
        if failures.empty?
          Operation::Ok.new(nil)
        else
          first = failures.first
          error = Dex::Error.new(first[:guard], first[:message], details: failures)
          Operation::Err.new(error)
        end
      end

      def callable?(*args, **kwargs)
        if args.size > 1
          raise ArgumentError, "callable? accepts at most one guard name, got #{args.size} arguments"
        end

        if args.first
          guard_name = args.first
          unless guard_name.is_a?(Symbol)
            raise ArgumentError, "guard name must be a Symbol, got: #{guard_name.inspect}"
          end
          unless _guard_list.any? { |g| g.name == guard_name }
            raise ArgumentError, "unknown guard :#{guard_name}. Declared: #{_guard_list.map(&:name).map(&:inspect).join(", ")}"
          end
          instance = new(**kwargs)
          failures = instance.send(:_guard_evaluate)
          failures.none? { |f| f[:guard] == guard_name }
        else
          callable(**kwargs).ok?
        end
      end

      private

      def _guard_own
        @_guards ||= []
      end

      def _guard_normalize_requires!(code, requires)
        return [] if requires.nil?

        deps = Array(requires)
        invalid = deps.reject { |d| d.is_a?(Symbol) }
        if invalid.any?
          raise ArgumentError,
            "guard :#{code} requires: must be Symbol(s), got: #{invalid.map(&:inspect).join(", ")}"
        end

        all_names = _guard_list.map(&:name)
        deps.each do |dep|
          unless all_names.include?(dep)
            raise ArgumentError,
              "guard :#{code} requires :#{dep}, but no guard with that name has been declared"
          end
        end

        deps.freeze
      end

      def _guard_validate_unique!(code)
        all_names = _guard_list.map(&:name)
        if all_names.include?(code)
          raise ArgumentError, "duplicate guard name :#{code}"
        end
      end
    end

    def _guard_wrap
      guards = self.class._guard_list
      return yield if guards.empty?

      failures = _guard_evaluate
      unless failures.empty?
        first = failures.first
        error!(first[:guard], first[:message], details: failures)
      end

      yield
    end

    private

    def _guard_evaluate_all
      guards = self.class._guard_list
      return [] if guards.empty?

      blocked_names = Set.new
      results = []

      guards.each do |guard|
        if guard.requires.any? { |dep| blocked_names.include?(dep) }
          blocked_names << guard.name
          results << { name: guard.name, passed: false, skipped: true }
          next
        end

        threat = catch(:_dex_halt) { instance_exec(&guard.block) }
        if threat.is_a?(Operation::Halt)
          raise ArgumentError,
            "guard :#{guard.name} must return truthy/falsy, not call error!/success!"
        end

        if threat
          blocked_names << guard.name
          results << { name: guard.name, passed: false, message: guard.message || guard.name.to_s }
        else
          results << { name: guard.name, passed: true }
        end
      end

      results
    end

    def _guard_evaluate
      _guard_evaluate_all.filter_map do |r|
        next if r[:passed] || r[:skipped]

        { guard: r[:name], message: r[:message] }
      end
    end
  end
end
