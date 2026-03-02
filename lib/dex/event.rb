# frozen_string_literal: true

require "set"

# Modules loaded before class body (no reference to Dex::Event needed)
require_relative "event/execution_state"
require_relative "event/metadata"
require_relative "event/trace"
require_relative "event/suppression"

module Dex
  class Event
    RESERVED_PROP_NAMES = %i[
      id timestamp trace_id caused_by_id caused_by
      context publish metadata sync
    ].to_set.freeze

    include PropsSetup
    include TypeCoercion

    def self._warn(message)
      Dex.warn("Event: #{message}")
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

    # Tracing
    def trace(&block)
      Trace.with_event(self, &block)
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
