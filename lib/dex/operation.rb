module Dex
  module RecordWrapper
    def perform(*, **)
      # Operation::Record.create!(
      #   name: self.class.name,
      #   params: self.params.as_json
      # )
      super
    end
  end

  module ParamsWrapper
    @_params_schema = Dex::Parameters

    def initialize(*args, **kwargs)
      if !kwargs.empty?
        @params = self.class._params_schema.new(kwargs)
      end
      super
    end

    module ClassMethods
      def params(&block)
        klass = Class.new(Dex::Parameters, &block)
        const_set(:Params, klass)
        @_params_schema = klass
      end

      def _params_schema
        @_params_schema
      end
    end

    def self.prepended(base)
      base.attr_reader :params

      class << base
        prepend ClassMethods
      end
    end
  end

  class Operation
    def initialize(*, **); end
    def perform(*, **); end

    def self.inherited(base)
      base.prepend RecordWrapper
      base.prepend ParamsWrapper
    end
  end
end
