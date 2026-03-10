# frozen_string_literal: true

module Dex
  module OnceWrapper
    extend Dex::Concern

    module ClassMethods
      def once(*props, expires_in: nil, &block)
        if settings_for(:once)[:defined]
          raise ArgumentError, "once can only be declared once per operation"
        end

        record_settings = settings_for(:record)
        if record_settings[:enabled] == false
          raise ArgumentError, "once requires record to be enabled"
        end

        if record_settings[:result] == false
          raise ArgumentError, "once requires result recording (cannot use record result: false)"
        end

        if block && props.any?
          raise ArgumentError, "once accepts either prop names or a block, not both"
        end

        if expires_in && !expires_in.is_a?(Numeric)
          raise ArgumentError, "once :expires_in must be a duration, got: #{expires_in.inspect}"
        end

        _once_validate_props!(props) if props.any?

        set(:once,
          defined: true,
          props: props.any? ? props : nil,
          block: block || nil,
          expires_in: expires_in)
      end

      def clear_once!(key = nil, **props)
        derived = if key.is_a?(String)
          key
        elsif props.any?
          _once_build_scoped_key(props)
        else
          raise ArgumentError, "pass a String key or keyword arguments matching the once props"
        end
        _once_validate_backend!
        Dex.record_backend.update_record_by_once_key(derived, once_key: nil)
      end

      def _once_build_scoped_key(props_hash)
        segments = props_hash.sort_by { |k, _| k.to_s }.map do |k, v|
          "#{k}=#{URI.encode_www_form_component(v.to_s)}"
        end
        "#{name}/#{segments.join("/")}"
      end

      private

      def _once_required_fields
        fields =
          if respond_to?(:_record_required_fields, true)
            send(:_record_required_fields)
          else
            []
          end

        fields << "once_key"
        fields << "once_key_expires_at" if settings_for(:once)[:expires_in]
        fields.uniq
      end

      def _once_validate_backend!
        unless Dex.record_backend
          raise "once requires a record backend (configure Dex.record_class)"
        end

        Dex.record_backend.ensure_fields!(_once_required_fields, feature: "once")
      end

      def _once_validate_props!(prop_names)
        return unless respond_to?(:literal_properties)

        defined_names = literal_properties.map(&:name).to_set
        unknown = prop_names.reject { |p| defined_names.include?(p) }
        return if unknown.empty?

        raise ArgumentError,
          "once references unknown prop(s): #{unknown.map(&:inspect).join(", ")}. " \
          "Defined: #{defined_names.map(&:inspect).join(", ")}"
      end
    end

    def once(key)
      @_once_key = key
      @_once_key_explicit = true
      self
    end

    def _once_wrap
      return yield unless _once_active?

      key = _once_derive_key
      return yield if key.nil? && _once_key_explicit?

      _once_ensure_backend!

      raise "once key must not be nil" if key.nil?

      expires_in = self.class.settings_for(:once)[:expires_in]
      expires_at = expires_in ? _once_current_time + expires_in : nil

      existing = Dex.record_backend.find_by_once_key(key)
      if existing
        _once_finalize_duplicate!(existing)
        return _once_replay!(existing)
      end

      expired = Dex.record_backend.find_expired_once_key(key)
      Dex.record_backend.update_record(expired.id.to_s, once_key: nil) if expired

      _once_claim!(key, expires_at) { yield }
    end

    private

    def _once_key_explicit?
      defined?(@_once_key_explicit) && @_once_key_explicit
    end

    def _once_active?
      return true if _once_key_explicit?
      self.class.settings_for(:once).fetch(:defined, false)
    end

    def _once_ensure_backend!
      self.class.send(:_once_validate_backend!)
    end

    def _once_derive_key
      return @_once_key if _once_key_explicit?

      settings = self.class.settings_for(:once)

      if settings[:block]
        instance_exec(&settings[:block])
      elsif settings[:props]
        props_hash = settings[:props].each_with_object({}) { |p, h| h[p] = public_send(p) }
        self.class._once_build_scoped_key(props_hash)
      else
        hash = {}
        if self.class.respond_to?(:literal_properties)
          self.class.literal_properties.each { |p| hash[p.name] = public_send(p.name) }
        end
        self.class._once_build_scoped_key(hash)
      end
    end

    def _once_claim!(key, expires_at)
      begin
        _once_acquire_key!(key, expires_at)
      rescue => e
        if Dex.record_backend.unique_constraint_error?(e)
          existing = Dex.record_backend.find_by_once_key(key)
          if existing
            _once_finalize_duplicate!(existing)
            return _once_replay!(existing)
          end

          raise "once key #{key.inspect} is claimed by another in-flight execution"
        end
        raise
      end
      yield
    end

    def _once_acquire_key!(key, expires_at)
      if _once_has_pending_record?
        Dex.record_backend.update_record(@_dex_record_id,
          once_key: key, once_key_expires_at: expires_at)
      else
        record = Dex.record_backend.create_record(
          name: self.class.name,
          once_key: key,
          once_key_expires_at: expires_at,
          status: "pending"
        )
        @_dex_record_id = record.id.to_s
      end
    end

    def _once_has_pending_record?
      defined?(@_dex_record_id) && @_dex_record_id
    end

    def _once_finalize_duplicate!(source_record)
      return unless _once_has_pending_record?

      attrs = { performed_at: _once_current_time }
      if source_record.status == "error"
        attrs[:status] = "error"
        attrs[:error_code] = source_record.error_code
        attrs[:error_message] = source_record.error_message
        attrs[:error_details] = source_record.respond_to?(:error_details) ? source_record.error_details : nil
      else
        attrs[:status] = "completed"
        attrs[:result] = source_record.respond_to?(:result) ? source_record.result : nil
      end
      Dex.record_backend.update_record(@_dex_record_id, attrs)
    rescue => e
      Dex.warn("Failed to finalize replayed record: #{e.message}")
    end

    def _once_replay!(record)
      case record.status
      when "completed"
        _once_replay_success(record)
      when "error"
        _once_replay_error(record)
      end
    end

    def _once_replay_success(record)
      stored = record.respond_to?(:result) ? record.result : nil
      success_type = self.class.respond_to?(:_success_type) && self.class._success_type

      if success_type && stored
        self.class.send(:_coerce_value, success_type, stored)
      elsif stored.is_a?(Hash) && stored.key?("_dex_value")
        stored["_dex_value"]
      else
        stored
      end
    end

    def _once_replay_error(record)
      raise Dex::Error.new(
        record.error_code.to_sym,
        record.error_message,
        details: record.respond_to?(:error_details) ? record.error_details : nil
      )
    end

    def _once_current_time
      Time.respond_to?(:current) ? Time.current : Time.now
    end
  end
end
