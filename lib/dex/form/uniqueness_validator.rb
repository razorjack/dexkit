# frozen_string_literal: true

module Dex
  class Form
    class UniquenessValidator < ActiveModel::EachValidator
      def check_validity!
        if options.key?(:model) && !options[:model].is_a?(Class)
          raise ArgumentError, "uniqueness :model must be a Class, got #{options[:model].inspect}"
        end
        if options.key?(:conditions) && !options[:conditions].respond_to?(:call)
          raise ArgumentError, "uniqueness :conditions must be callable"
        end
      end

      def validate_each(form, attribute, value)
        return if value.blank?

        model_class = _resolve_model_class(form)
        return unless model_class

        column = options[:attribute] || attribute
        query = _build_query(model_class, column, value)
        query = _apply_scope(query, form)
        query = _apply_conditions(query, form)
        query = _exclude_current_record(query, form)

        form.errors.add(attribute, options[:message] || :taken) if query.exists?
      end

      private

      def _resolve_model_class(form)
        return options[:model] if options[:model]
        return form.class._model_class if form.class.respond_to?(:_model_class) && form.class._model_class

        _infer_model_class(form)
      end

      def _infer_model_class(form)
        class_name = form.class.name
        return unless class_name

        model_name = class_name.sub(/Form\z/, "")
        return if model_name == class_name

        klass = Object.const_get(model_name)
        klass.respond_to?(:where) ? klass : nil
      rescue NameError
        nil
      end

      def _build_query(model_class, column, value)
        return model_class.where(column => value) unless options[:case_sensitive] == false && value.is_a?(String)

        if model_class.respond_to?(:arel_table)
          model_class.where(model_class.arel_table[column].lower.eq(value.downcase))
        elsif _mongoid_model_class?(model_class)
          model_class.where(column => /\A#{Regexp.escape(value)}\z/i)
        else
          model_class.where(column => value)
        end
      end

      def _apply_scope(query, form)
        Array(options[:scope]).each do |scope_attr|
          query = query.where(scope_attr => form.public_send(scope_attr))
        end
        query
      end

      def _apply_conditions(query, form)
        return query unless options[:conditions]

        callable = options[:conditions]
        if callable.arity.zero?
          query.instance_exec(&callable)
        else
          query.instance_exec(form, &callable)
        end
      end

      def _exclude_current_record(query, form)
        return query unless form.record&.persisted?

        if _mongoid_record?(form.record)
          return query.where(:_id.ne => form.record.id)
        end

        pk = form.record.class.primary_key
        query.where.not(pk => form.record.public_send(pk))
      end

      def _mongoid_model_class?(model_class)
        defined?(Mongoid::Document) && model_class.include?(Mongoid::Document)
      end

      def _mongoid_record?(record)
        _mongoid_model_class?(record.class)
      end
    end
  end
end
