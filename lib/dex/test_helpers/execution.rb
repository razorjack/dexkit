# frozen_string_literal: true

module Dex
  module TestHelpers
    def call_operation(*args, **params)
      klass = _dex_resolve_subject(args)
      klass.new(**params).safe.call
    end

    def call_operation!(*args, **params)
      klass = _dex_resolve_subject(args)
      klass.new(**params).call
    end

    private

    def _dex_resolve_subject(args)
      if args.first.is_a?(Class) && args.first < Dex::Operation
        args.first
      elsif _dex_test_subject
        _dex_test_subject
      else
        raise ArgumentError,
          "No operation class specified. Pass it as the first argument or use `testing MyOperation` in your test class."
      end
    end
  end
end
