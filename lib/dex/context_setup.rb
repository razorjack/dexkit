# frozen_string_literal: true

module Dex
  # Context DSL for Operation and Event (Literal::Properties-backed).
  #
  # Maps declared props to ambient context keys so they can be auto-filled
  # from Dex.context when not passed explicitly as kwargs.
  module ContextSetup
    extend Dex::Concern

    module ClassMethods
      include ContextDSL

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

      def _context_prop_declared?(name)
        respond_to?(:literal_properties) && literal_properties.any? { |p| p.name == name }
      end
    end
  end
end
