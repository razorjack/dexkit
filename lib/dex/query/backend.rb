# frozen_string_literal: true

module Dex
  class Query
    module Backend
      STRATEGIES = %i[eq not_eq contains starts_with ends_with gt gte lt lte in not_in].to_set.freeze

      module ActiveRecordAdapter
        module_function

        def apply(scope, strategy, column, value)
          table = scope.arel_table

          case strategy
          when :eq, :in
            scope.where(column => value)
          when :not_eq, :not_in
            scope.where.not(column => value)
          when :contains
            scope.where(table[column].matches("%#{sanitize_like(value)}%", "\\"))
          when :starts_with
            scope.where(table[column].matches("#{sanitize_like(value)}%", "\\"))
          when :ends_with
            scope.where(table[column].matches("%#{sanitize_like(value)}", "\\"))
          when :gt
            scope.where(table[column].gt(value))
          when :gte
            scope.where(table[column].gteq(value))
          when :lt
            scope.where(table[column].lt(value))
          when :lte
            scope.where(table[column].lteq(value))
          else
            raise ArgumentError, "Unknown strategy: #{strategy.inspect}"
          end
        end

        def sanitize_like(value)
          ActiveRecord::Base.sanitize_sql_like(value.to_s)
        end
      end

      module MongoidAdapter
        module_function

        def apply(scope, strategy, column, value)
          case strategy
          when :eq
            scope.where(column => value)
          when :not_eq
            scope.where(column.to_sym.ne => value)
          when :in
            scope.where(column.to_sym.in => Array(value))
          when :not_in
            scope.where(column.to_sym.nin => Array(value))
          when :contains
            scope.where(column => /#{Regexp.escape(value.to_s)}/i)
          when :starts_with
            scope.where(column => /\A#{Regexp.escape(value.to_s)}/i)
          when :ends_with
            scope.where(column => /#{Regexp.escape(value.to_s)}\z/i)
          when :gt
            scope.where(column.to_sym.gt => value)
          when :gte
            scope.where(column.to_sym.gte => value)
          when :lt
            scope.where(column.to_sym.lt => value)
          when :lte
            scope.where(column.to_sym.lte => value)
          else
            raise ArgumentError, "Unknown strategy: #{strategy.inspect}"
          end
        end
      end

      module_function

      def apply_strategy(scope, strategy, column, value)
        scope = normalize_scope(scope)
        adapter_for(scope).apply(scope, strategy, column, value)
      end

      def adapter_for(scope)
        scope = normalize_scope(scope)

        if defined?(Mongoid::Criteria) && scope.is_a?(Mongoid::Criteria)
          MongoidAdapter
        else
          ActiveRecordAdapter
        end
      end

      def normalize_scope(scope)
        return scope unless defined?(Mongoid::Criteria)
        return scope if scope.is_a?(Mongoid::Criteria)

        criteria = scope.criteria if scope.respond_to?(:criteria)
        criteria.is_a?(Mongoid::Criteria) ? criteria : scope
      rescue
        scope
      end
    end
  end
end
