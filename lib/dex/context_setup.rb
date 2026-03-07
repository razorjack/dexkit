# frozen_string_literal: true

module Dex
  # Shared context DSL for Operation and Event.
  #
  # Maps declared props to ambient context keys so they can be auto-filled
  # from Dex.context when not passed explicitly as kwargs.
  module ContextSetup
    extend Dex::Concern

    module ClassMethods
      def context(*names, **mappings)
        names.each do |name|
          unless name.is_a?(Symbol)
            raise ArgumentError, "context shorthand must be a Symbol, got: #{name.inspect}"
          end
          mappings[name] = name
        end

        raise ArgumentError, "context requires at least one mapping" if mappings.empty?

        mappings.each do |prop_name, context_key|
          unless _context_prop_declared?(prop_name)
            raise ArgumentError,
              "context references undeclared prop :#{prop_name}. Declare the prop before calling context."
          end
          unless context_key.is_a?(Symbol)
            raise ArgumentError,
              "context key must be a Symbol, got: #{context_key.inspect} for prop :#{prop_name}"
          end
        end

        _context_own.merge!(mappings)
      end

      def context_mappings
        parent = superclass.respond_to?(:context_mappings) ? superclass.context_mappings : {}
        parent.merge(_context_own)
      end

      def new(**kwargs)
        mappings = context_mappings
        unless mappings.empty?
          ambient = Dex.context
          mappings.each do |prop_name, context_key|
            next if kwargs.key?(prop_name)
            kwargs[prop_name] = ambient[context_key] if ambient.key?(context_key)
          end
        end
        super
      end

      private

      def _context_own
        @_context_own_mappings ||= {}
      end

      def _context_prop_declared?(name)
        respond_to?(:literal_properties) && literal_properties.any? { |p| p.name == name }
      end
    end
  end
end
