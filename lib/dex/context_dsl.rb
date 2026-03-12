# frozen_string_literal: true

module Dex
  # Shared context DSL extracted from ContextSetup.
  #
  # Provides the `context` class method, `context_mappings` inheritance,
  # and `_context_own` storage.  Includers must implement:
  #   _context_prop_declared?(name) → true/false
  # and may override:
  #   _context_field_label → "prop" | "field" (used in error messages)
  module ContextDSL
    def context(*names, **mappings)
      names.each do |name|
        unless name.is_a?(Symbol)
          raise ArgumentError, "context shorthand must be a Symbol, got: #{name.inspect}"
        end
        mappings[name] = name
      end

      raise ArgumentError, "context requires at least one mapping" if mappings.empty?

      label = _context_field_label
      mappings.each do |prop_name, context_key|
        unless _context_prop_declared?(prop_name)
          raise ArgumentError,
            "context references undeclared #{label} :#{prop_name}. Declare the #{label} before calling context."
        end
        unless context_key.is_a?(Symbol)
          raise ArgumentError,
            "context key must be a Symbol, got: #{context_key.inspect} for #{label} :#{prop_name}"
        end
      end

      _context_own.merge!(mappings)
    end

    def context_mappings
      parent = superclass.respond_to?(:context_mappings) ? superclass.context_mappings : {}
      parent.merge(_context_own)
    end

    private

    def _context_own
      @_context_own_mappings ||= {}
    end

    def _context_prop_declared?(_name)
      raise NotImplementedError, "#{self} must implement _context_prop_declared?"
    end

    def _context_field_label
      "prop"
    end
  end
end
