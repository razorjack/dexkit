# frozen_string_literal: true

module Dex
  class Query
    module Sorting
      extend Dex::Concern

      SortDef = Data.define(:name, :custom, :block)

      module ClassMethods
        def _sort_registry
          @_sort_registry ||= {}
        end

        def _sort_default
          return @_sort_default if defined?(@_sort_default)

          nil
        end

        def sort(*columns, default: nil, &block)
          if block
            raise ArgumentError, "Block sort requires exactly one column name." unless columns.size == 1

            name = columns.first.to_sym

            if _sort_registry.key?(name)
              raise ArgumentError, "Sort :#{name} is already declared."
            end

            _sort_registry[name] = SortDef.new(name: name, custom: true, block: block)
          else
            raise ArgumentError, "sort requires at least one column name." if columns.empty?

            columns.each do |col|
              col = col.to_sym

              if _sort_registry.key?(col)
                raise ArgumentError, "Sort :#{col} is already declared."
              end

              _sort_registry[col] = SortDef.new(name: col, custom: false, block: nil)
            end
          end

          if default
            if defined?(@_sort_default) && @_sort_default
              raise ArgumentError, "Default sort is already set to #{@_sort_default.inspect}."
            end

            bare = default.to_s.delete_prefix("-").to_sym
            unless _sort_registry.key?(bare)
              raise ArgumentError, "Default sort references unknown sort: #{bare.inspect}."
            end

            if default.to_s.start_with?("-") && _sort_registry[bare].custom
              raise ArgumentError, "Custom sorts cannot use the \"-\" prefix."
            end

            @_sort_default = default.to_s
          end
        end

        def sorts
          _sort_registry.keys
        end
      end

      private

      def _apply_sort(scope)
        sort_value = _current_sort
        return scope unless sort_value

        desc = sort_value.start_with?("-")
        bare = sort_value.delete_prefix("-").to_sym

        sort_def = self.class._sort_registry[bare]
        unless sort_def
          raise ArgumentError, "Unknown sort: #{bare.inspect}. Valid sorts: #{self.class._sort_registry.keys.join(", ")}"
        end

        if desc && sort_def.custom
          raise ArgumentError, "Custom sorts cannot use the \"-\" prefix."
        end

        if sort_def.custom
          instance_exec(scope, &sort_def.block)
        else
          scope.order(bare => desc ? :desc : :asc)
        end
      end
    end
  end
end
