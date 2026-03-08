# frozen_string_literal: true

module Dex
  class Operation
    module Explain
      def explain(**kwargs)
        instance = new(**kwargs)
        info = {}
        active = pipeline.steps.map(&:name).to_set

        info[:operation] = name || "(anonymous)"
        info[:props] = _explain_props(instance)
        info[:context] = _explain_context(instance, kwargs)
        info[:guards] = active.include?(:guard) ? _explain_guards(instance) : { passed: true, results: [] }
        info[:once] = active.include?(:once) ? _explain_once(instance) : { active: false }
        info[:lock] = active.include?(:lock) ? _explain_lock(instance) : { active: false }
        info[:record] = active.include?(:record) ? _explain_record : { enabled: false }
        info[:transaction] = active.include?(:transaction) ? _explain_transaction : { enabled: false }
        info[:rescue_from] = active.include?(:rescue) ? _explain_rescue : {}
        info[:callbacks] = active.include?(:callback) ? _explain_callbacks : { before: 0, after: 0, around: 0 }

        # Let custom middleware contribute via _name_explain class methods
        pipeline.steps.each do |step|
          method_name = :"_#{step.name}_explain"
          send(method_name, instance, info) if respond_to?(method_name, true)
        end

        info[:pipeline] = pipeline.steps.map(&:name)
        info[:callable] = _explain_callable?(info)
        info.freeze
      end

      private

      def _explain_callable?(info)
        return false unless info[:guards][:passed]

        if info[:once][:active]
          return false if ONCE_BLOCKING_STATUSES.include?(info[:once][:status])
        end

        true
      end

      ONCE_BLOCKING_STATUSES = %i[invalid pending misconfigured unavailable].freeze

      def _explain_props(instance)
        return {} unless respond_to?(:literal_properties)

        literal_properties.each_with_object({}) do |prop, hash|
          hash[prop.name] = instance.public_send(prop.name)
        end
      end

      def _explain_context(instance, explicit_kwargs)
        mappings = respond_to?(:context_mappings) ? context_mappings : {}
        return { resolved: {}, mappings: {}, source: {} } if mappings.empty?

        ambient = Dex.context
        resolved = {}
        source = {}

        mappings.each do |prop_name, context_key|
          resolved[prop_name] = instance.public_send(prop_name)
          source[prop_name] = if explicit_kwargs.key?(prop_name)
            :explicit
          elsif ambient.key?(context_key)
            :ambient
          else
            :default
          end
        end

        { resolved: resolved, mappings: mappings, source: source }
      end

      def _explain_guards(instance)
        all_results = instance.send(:_guard_evaluate_all)
        results = all_results.map do |r|
          entry = { name: r[:name], passed: r[:passed] }
          entry[:message] = r[:message] if r[:message]
          entry[:skipped] = true if r[:skipped]
          entry
        end
        { passed: results.all? { |r| r[:passed] }, results: results }
      end

      def _explain_once(instance)
        settings = settings_for(:once)
        return { active: false } unless settings.fetch(:defined, false)

        key = instance.send(:_once_derive_key)
        {
          active: true,
          key: key,
          status: _explain_once_status(key),
          expires_in: settings[:expires_in]
        }
      end

      def _explain_once_status(key)
        return :invalid if key.nil?
        return :misconfigured if name.nil?
        return :misconfigured unless pipeline.steps.any? { |s| s.name == :record }
        return :unavailable unless Dex.record_backend
        return :misconfigured unless Dex.record_backend.has_field?("once_key")

        settings = settings_for(:once)
        if settings[:expires_in] && !Dex.record_backend.has_field?("once_key_expires_at")
          return :misconfigured
        end

        existing = Dex.record_backend.find_by_once_key(key)
        return :exists if existing

        if Dex.record_backend.has_field?("once_key_expires_at")
          expired = Dex.record_backend.find_expired_once_key(key)
          return :expired if expired
        end

        pending = Dex.record_backend.find_pending_once_key(key)
        return :pending if pending

        :fresh
      end

      def _explain_lock(instance)
        settings = settings_for(:advisory_lock)
        return { active: false } unless settings.fetch(:enabled, false)

        { active: true, key: instance.send(:_lock_key), timeout: settings[:timeout] }
      end

      def _explain_record
        settings = settings_for(:record)
        enabled = settings.fetch(:enabled, true) && !!Dex.record_backend && !!name
        return { enabled: false } unless enabled

        {
          enabled: true,
          params: settings.fetch(:params, true),
          result: settings.fetch(:result, true)
        }
      end

      def _explain_transaction
        settings = settings_for(:transaction)
        return { enabled: false } unless settings.fetch(:enabled, true)

        adapter_name = settings.fetch(:adapter, Dex.transaction_adapter)
        adapter = Operation::TransactionAdapter.for(adapter_name)
        { enabled: !adapter.nil? }
      end

      def _explain_rescue
        handlers = respond_to?(:_rescue_handlers) ? _rescue_handlers : []
        handlers.each_with_object({}) do |h, hash|
          hash[h[:exception_class].name] = h[:code]
        end
      end

      def _explain_callbacks
        return { before: 0, after: 0, around: 0 } unless respond_to?(:_callback_list)

        {
          before: _callback_list(:before).size,
          after: _callback_list(:after).size,
          around: _callback_list(:around).size
        }
      end
    end
  end
end
