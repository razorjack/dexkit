# frozen_string_literal: true

module Dex
  module TestLog
    Entry = Data.define(:type, :name, :operation_class, :params, :result, :duration, :caller_location)

    @_entries = []
    @_mutex = Mutex.new

    class << self
      def record(entry)
        @_mutex.synchronize { @_entries << entry }
      end

      def calls
        @_mutex.synchronize { @_entries.dup }
      end

      def clear!
        @_mutex.synchronize { @_entries.clear }
      end

      def size
        @_mutex.synchronize { @_entries.size }
      end

      def empty?
        @_mutex.synchronize { @_entries.empty? }
      end

      def find(klass, **params)
        @_mutex.synchronize do
          @_entries.select do |entry|
            next false unless entry.operation_class == klass
            params.all? { |k, v| entry.params[k] == v }
          end
        end
      end

      def summary
        entries = calls
        return "No operations called." if entries.empty?

        lines = ["Operations called (#{entries.size}):"]
        entries.each_with_index do |entry, i|
          status = entry.result.ok? ? "OK" : "ERR(#{entry.result.code})"
          duration_ms = entry.duration ? format("%.1fms", entry.duration * 1000) : "n/a"
          lines << "  #{i + 1}. #{entry.name} [#{status}] #{duration_ms}"
          lines << "     params: #{entry.params.inspect}" unless entry.params.nil? || entry.params.empty?
        end
        lines.join("\n")
      end
    end
  end
end
