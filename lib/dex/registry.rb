# frozen_string_literal: true

module Dex
  module Registry
    def self.extended(base)
      base.instance_variable_set(:@_registry, Set.new)
    end

    def inherited(subclass)
      super
      _dex_registry.add(subclass)
    end

    def registry
      live = _dex_registry.select { |k| k.name && _dex_reachable?(k) }
      _dex_registry.replace(live)
      live.to_set.freeze
    end

    def deregister(klass)
      _dex_registry.delete(klass)
    end

    def clear!
      _dex_registry.clear
    end

    def description(text = nil)
      if !text.nil?
        raise ArgumentError, "description must be a String" unless text.is_a?(String)

        @_description = text
      else
        defined?(@_description) ? @_description : _dex_parent_description
      end
    end

    private

    def _dex_reachable?(klass)
      Object.const_get(klass.name) == klass
    rescue NameError
      false
    end

    def _dex_registry
      if instance_variable_defined?(:@_registry)
        @_registry
      elsif superclass.respond_to?(:_dex_registry, true)
        superclass.send(:_dex_registry)
      else
        @_registry = Set.new
      end
    end

    def _dex_parent_description
      return nil unless superclass.respond_to?(:description)
      return nil if superclass.instance_variable_defined?(:@_registry)

      superclass.description
    end
  end
end
