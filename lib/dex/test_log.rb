# frozen_string_literal: true

module Dex
  module TestLog
    Entry = Data.define(
      :type,
      :name,
      :operation_class,
      :params,
      :result,
      :duration,
      :caller_location,
      :execution_id,
      :trace_id,
      :trace
    )

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
        nodes = entries.each_with_index.map { |entry, index| { entry: entry, index: index } }
        by_id = nodes.to_h { |node| [node[:entry].execution_id, node] }
        children = Hash.new { |hash, key| hash[key] = [] }
        roots = []

        nodes.each do |node|
          parent_id = _parent_operation_id(node[:entry])
          if parent_id && by_id[parent_id]
            children[parent_id] << node
          else
            roots << node
          end
        end

        counter = 0
        render = lambda do |node, depth|
          counter += 1
          entry = node[:entry]
          status = entry.result.ok? ? "OK" : "ERR(#{entry.result.code})"
          duration_ms = entry.duration ? format("%.1fms", entry.duration * 1000) : "n/a"
          indent = "   " * depth
          id = entry.execution_id ? " (#{_display_id(entry.execution_id)})" : ""

          lines << "  #{indent}#{counter}. #{entry.name}#{id} [#{status}] #{duration_ms}"
          lines << "  #{indent}   params: #{entry.params.inspect}" unless entry.params.nil? || entry.params.empty?

          children.fetch(entry.execution_id, []).sort_by { |child| child[:index] }.each do |child|
            render.call(child, depth + 1)
          end
        end

        roots.sort_by { |node| node[:index] }.each { |node| render.call(node, 0) }
        lines.join("\n")
      end

      private

      def _frame_type(frame)
        return unless frame

        (frame[:type] || frame["type"])&.to_sym
      end

      def _display_id(id)
        prefix, suffix = id.to_s.split("_", 2)
        return id.to_s unless suffix

        "#{prefix}_#{suffix[0, 7]}"
      end

      def _parent_operation_id(entry)
        frames = Array(entry.trace)[0...-1]
        parent = frames.reverse.find { |frame| _frame_type(frame) == :operation }
        parent && (parent[:id] || parent["id"])
      end
    end
  end
end
