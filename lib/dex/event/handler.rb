# frozen_string_literal: true

module Dex
  class Event
    class Handler
      include Dex::Executable

      attr_reader :event

      def self.on(*event_classes)
        event_classes.each do |ec|
          Event.validate_event_class!(ec)
          Bus.subscribe(ec, self)
        end
      end

      def self.retries(count, **opts)
        raise ArgumentError, "retries count must be a positive Integer" unless count.is_a?(Integer) && count > 0

        if opts.key?(:wait)
          wait = opts[:wait]
          unless wait.is_a?(Numeric) || wait.is_a?(Proc)
            raise ArgumentError, "wait: must be Numeric or Proc"
          end
        end

        @_event_handler_retries = { count: count, **opts }
      end

      def self._event_handler_retry_config
        if defined?(@_event_handler_retries)
          @_event_handler_retries
        elsif superclass.respond_to?(:_event_handler_retry_config)
          superclass._event_handler_retry_config
        end
      end

      def self._event_handle(event)
        instance = new
        instance.instance_variable_set(:@event, event)
        instance.send(:call)
      end

      def self._event_handle_from_payload(event_class_name, payload, metadata_hash)
        event_class = Object.const_get(event_class_name)
        event = _event_reconstruct(event_class, payload, metadata_hash)
        _event_handle(event)
      end

      class << self
        private

        def _event_reconstruct(event_class, payload, metadata_hash)
          coerced = event_class.send(:_coerce_serialized_hash, payload)
          instance = event_class.allocate

          event_class.literal_properties.each do |prop|
            instance.instance_variable_set(:"@#{prop.name}", coerced[prop.name])
          end

          metadata = Event::Metadata.new(
            id: metadata_hash["id"],
            timestamp: Time.parse(metadata_hash["timestamp"]),
            trace_id: metadata_hash["trace_id"],
            caused_by_id: metadata_hash["caused_by_id"],
            context: metadata_hash["context"]
          )
          instance.instance_variable_set(:@metadata, metadata)
          instance.freeze
          instance
        end
      end

      use TransactionWrapper
      use CallbackWrapper

      transaction false
      private :call

      # Guard must be defined after `include Executable` (which defines #call).
      def self.method_added(method_name)
        super

        if method_name == :call
          raise ArgumentError, "#{name || "Handler"} must not define #call — define #perform instead"
        end

        private :perform if method_name == :perform
      end

      def perform
        raise NotImplementedError, "#{self.class.name} must implement #perform"
      end
    end
  end
end
