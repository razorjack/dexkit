# frozen_string_literal: true

module Dex
  module Executable
    def self.included(base)
      base.include(Dex::Settings)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def inherited(subclass)
        subclass.instance_variable_set(:@_pipeline, pipeline.dup)
        super
      end

      def pipeline
        @_pipeline ||= Pipeline.new
      end

      def use(mod, as: nil, wrap: nil, before: nil, after: nil, at: nil)
        step_name = as || _derive_step_name(mod)
        wrap_method = wrap || :"_#{step_name}_wrap"
        pipeline.add(step_name, method: wrap_method, before: before, after: after, at: at)
        include mod
      end

      private

      def _derive_step_name(mod)
        base = mod.name&.split("::")&.last
        raise ArgumentError, "anonymous modules require explicit as: parameter" unless base

        base.sub(/Wrapper\z/, "")
          .gsub(/([a-z])([A-Z])/, '\1_\2')
          .downcase
          .to_sym
      end
    end

    def call
      self.class.pipeline.execute(self) { perform }
    end
  end
end
