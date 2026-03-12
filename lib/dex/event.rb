# frozen_string_literal: true

# Modules loaded before class body (no reference to Dex::Event needed)
require_relative "event/execution_state"
require_relative "event/metadata"
require_relative "event/trace"
require_relative "event/suppression"

module Dex
  class Event
    RESERVED_PROP_NAMES = %i[
      id timestamp trace_id caused_by_id caused_by event_ancestry
      context publish metadata sync
    ].to_set.freeze

    include PropsSetup
    include TypeCoercion
    include ContextSetup

    extend Registry

    class << self
      def to_h
        Export.build_hash(self)
      end

      def to_json_schema
        Export.build_json_schema(self)
      end

      def export(format: :hash)
        unless %i[hash json_schema].include?(format)
          raise ArgumentError, "unknown format: #{format.inspect}. Known: :hash, :json_schema"
        end

        sorted = registry.sort_by(&:name)
        sorted.map do |klass|
          case format
          when :hash then klass.to_h
          when :json_schema then klass.to_json_schema
          end
        end
      end
    end

    def self._warn(message)
      Dex.warn("Event: #{message}")
    end

    def self.validate_event_class!(klass)
      return if klass.is_a?(Class) && klass < Dex::Event

      raise ArgumentError, "#{klass.inspect} is not a Dex::Event subclass"
    end

    # --- Instance ---

    attr_reader :metadata

    def after_initialize
      @metadata = Metadata.build
      freeze
    end

    # Metadata delegates
    def id = metadata.id
    def timestamp = metadata.timestamp
    def trace_id = metadata.trace_id
    def caused_by_id = metadata.caused_by_id
    def event_ancestry = metadata.event_ancestry
    def context = metadata.context

    # Publishing
    def publish(sync: false)
      Bus.publish(self, sync: sync)
    end

    def self.publish(sync: false, caused_by: nil, **kwargs)
      if caused_by
        Trace.with_event(caused_by) do
          new(**kwargs).publish(sync: sync)
        end
      else
        new(**kwargs).publish(sync: sync)
      end
    end

    # Suppression
    def self.suppress(*classes, &block)
      Suppression.suppress(*classes, &block)
    end

    # Serialization
    def as_json
      {
        "type" => self.class.name,
        "payload" => _props_as_json,
        "metadata" => metadata.as_json
      }
    end
  end
end

# Classes loaded after Event is defined (they reference Dex::Event)
require_relative "event/bus"
require_relative "event/handler"
require_relative "event/processor"
require_relative "event/export"
