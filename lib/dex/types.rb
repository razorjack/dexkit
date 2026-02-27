# frozen_string_literal: true

module Dex
  module Types
    # Extend in your Types module to add Ref() method
    module Extension
      def Ref(model_class, lock: false)
        Dry::Types["any"].constructor do |value|
          next value if value.is_a?(model_class)
          next value if value.nil?

          scope = lock ? model_class.lock : model_class
          scope.find(value)
        end.meta(dex_ref_class: model_class)
      end
    end
  end
end
