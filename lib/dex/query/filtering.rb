# frozen_string_literal: true

module Dex
  class Query
    module Filtering
      extend Dex::Concern

      FilterDef = Data.define(:name, :strategy, :column, :block, :optional)

      module ClassMethods
        def _filter_registry
          @_filter_registry ||= {}
        end

        def filter(name, strategy = :eq, column: nil, &block)
          name = name.to_sym

          if _filter_registry.key?(name)
            raise ArgumentError, "Filter :#{name} is already declared."
          end

          unless respond_to?(:literal_properties) && literal_properties.any? { |p| p.name == name }
            raise ArgumentError, "Filter :#{name} requires a prop with the same name."
          end

          optional = _prop_optional?(name)

          if block
            _filter_registry[name] = FilterDef.new(name: name, strategy: nil, column: nil, block: block, optional: optional)
          else
            unless Backend::STRATEGIES.include?(strategy)
              raise ArgumentError, "Unknown filter strategy: #{strategy.inspect}. " \
                                   "Valid strategies: #{Backend::STRATEGIES.to_a.join(", ")}"
            end

            _filter_registry[name] = FilterDef.new(
              name: name,
              strategy: strategy,
              column: (column || name).to_sym,
              block: nil,
              optional: optional
            )
          end
        end

        def filters
          _filter_registry.keys
        end
      end

      private

      def _apply_filters(scope)
        self.class._filter_registry.each_value do |filter_def|
          value = public_send(filter_def.name)

          next if value.nil? && filter_def.optional
          next if (filter_def.strategy == :in || filter_def.strategy == :not_in) && value.respond_to?(:empty?) && value.empty?

          result = if filter_def.block
            instance_exec(scope, value, &filter_def.block)
          else
            Backend.apply_strategy(scope, filter_def.strategy, filter_def.column, value)
          end

          scope = result unless result.nil?
        end

        scope
      end
    end
  end
end
