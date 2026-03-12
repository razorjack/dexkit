# frozen_string_literal: true

module Dex
  class Form
    # Context DSL for Form (ActiveModel::Attributes-backed).
    #
    # Same DSL as Operation/Event context, but checks attribute_names
    # instead of literal_properties. Injection happens in Form#initialize.
    module Context
      extend Dex::Concern

      module ClassMethods
        include ContextDSL

        private

        def _context_prop_declared?(name)
          attribute_names.include?(name.to_s)
        end

        def _context_field_label
          "field"
        end
      end
    end
  end
end
