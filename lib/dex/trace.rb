# frozen_string_literal: true

module Dex
  module Trace
    FIBER_KEY = :_dex_trace
    FRAME_TYPES = %i[actor operation handler].freeze

    class << self
      def start(actor: nil, trace_id: nil)
        previous = _dump_state
        _set_state(trace_id: (trace_id || Dex::Id.generate("tr_")).to_s, frames: [], event_context: nil)
        _state[:frames] << _normalize_actor(actor) if actor
        yield
      ensure
        _restore_state(previous)
      end

      def ensure_started!(trace_id: nil)
        return false if active?

        _state[:trace_id] = (trace_id || Dex::Id.generate("tr_")).to_s
        true
      end

      def active?
        !trace_id.nil?
      end

      def with_frame(frame)
        auto_started = ensure_started!
        pushed = false
        push(frame)
        pushed = true
        yield
      ensure
        pop if pushed
        stop! if auto_started
      end

      def with_event_context(event)
        auto_started = ensure_started!(trace_id: event.trace_id)
        previous = _state[:event_context]
        _state[:event_context] = _build_event_context(event)
        yield
      ensure
        _state[:event_context] = previous
        stop! if auto_started
      end

      def restore_event_context(event_id:, trace_id:, event_class: nil, event_ancestry: [])
        previous = _dump_state
        effective_trace_id = trace_id&.to_s || _state[:trace_id]
        _set_state(
          trace_id: effective_trace_id,
          frames: _normalize_frames(_state[:frames]),
          event_context: {
            id: event_id&.to_s,
            trace_id: effective_trace_id,
            event_class: event_class,
            event_ancestry: Array(event_ancestry).compact.map(&:to_s)
          }
        )
        yield
      ensure
        _restore_state(previous)
      end

      def push(frame)
        _state[:frames] << _normalize_frame(frame)
      end

      def pop
        _state[:frames].pop
      end

      def current
        _deep_copy(_state[:frames])
      end

      def trace_id
        _state[:trace_id]
      end

      def current_id
        _state[:frames].last&.dig(:id)
      end

      def actor
        frame = _state[:frames].find { |entry| entry[:type] == :actor }
        frame ? _deep_copy(frame) : nil
      end

      def current_event_id
        current_event_context&.dig(:id)
      end

      def current_event_context
        context = _state[:event_context]
        return _deep_copy(context) if context

        handler = _state[:frames].reverse.find { |frame| frame[:type] == :handler && frame[:event_id] }
        return nil unless handler

        {
          id: handler[:event_id],
          trace_id: trace_id,
          event_class: handler[:event_class],
          event_ancestry: _deep_copy(Array(handler[:event_ancestry]))
        }
      end

      def dump
        return nil unless active?

        data = {
          trace_id: trace_id,
          frames: current
        }
        data[:event_context] = _deep_copy(_state[:event_context]) if _state[:event_context]
        data
      end

      def restore(data)
        return yield unless data

        previous = _dump_state
        _set_state(
          trace_id: _fetch(data, :trace_id)&.to_s,
          frames: _normalize_frames(_fetch(data, :frames)),
          event_context: _normalize_event_context(_fetch(data, :event_context))
        )
        yield
      ensure
        _restore_state(previous)
      end

      def to_s
        current.filter_map { |frame| _format_frame(frame) }.join(" > ")
      end

      def clear!
        Fiber[FIBER_KEY] = nil
      end
      alias_method :stop!, :clear!

      private

      def _state
        Fiber[FIBER_KEY] ||= { trace_id: nil, frames: [], event_context: nil }
      end

      def _set_state(trace_id:, frames:, event_context:)
        Fiber[FIBER_KEY] = {
          trace_id: trace_id,
          frames: frames,
          event_context: event_context
        }
      end

      def _dump_state
        state = _state
        return nil unless state[:trace_id] || !state[:frames].empty? || state[:event_context]

        {
          trace_id: state[:trace_id],
          frames: _deep_copy(state[:frames]),
          event_context: _deep_copy(state[:event_context])
        }
      end

      def _restore_state(state)
        if state
          _set_state(
            trace_id: state[:trace_id],
            frames: _normalize_frames(state[:frames]),
            event_context: _normalize_event_context(state[:event_context])
          )
        else
          clear!
        end
      end

      def _normalize_frames(frames)
        Array(frames).map { |frame| _normalize_frame(frame) }
      end

      def _normalize_actor(actor)
        raise ArgumentError, "actor must be a Hash" unless actor.is_a?(Hash)

        normalized = _symbolize(actor)
        actor_type = normalized[:type]
        raise ArgumentError, "actor must include :type" if actor_type.nil? || actor_type.to_s.strip.empty?

        frame = { type: :actor, actor_type: actor_type.to_s }
        frame[:id] = normalized[:id].to_s if normalized.key?(:id) && !normalized[:id].nil?

        normalized.each do |key, value|
          next if %i[type id].include?(key)

          frame[key] = _deep_copy(value)
        end

        frame
      end

      def _normalize_frame(frame)
        raise ArgumentError, "trace frame must be a Hash" unless frame.is_a?(Hash)

        normalized = _symbolize(frame)
        type = normalized[:type]&.to_sym
        raise ArgumentError, "trace frame type is required" unless type
        raise ArgumentError, "unknown trace frame type: #{type.inspect}" unless FRAME_TYPES.include?(type)

        normalized[:type] = type
        normalized[:id] = normalized[:id].to_s if normalized.key?(:id) && !normalized[:id].nil?
        normalized[:actor_type] = normalized[:actor_type].to_s if normalized.key?(:actor_type) && !normalized[:actor_type].nil?
        normalized[:event_id] = normalized[:event_id].to_s if normalized.key?(:event_id) && !normalized[:event_id].nil?
        normalized[:event_ancestry] = Array(normalized[:event_ancestry]).compact.map(&:to_s) if normalized.key?(:event_ancestry)
        normalized
      end

      def _normalize_event_context(context)
        return nil unless context

        {
          id: _fetch(context, :id)&.to_s,
          trace_id: _fetch(context, :trace_id)&.to_s,
          event_class: _fetch(context, :event_class),
          event_ancestry: Array(_fetch(context, :event_ancestry)).compact.map(&:to_s)
        }
      end

      def _build_event_context(event)
        {
          id: event.id.to_s,
          trace_id: event.trace_id.to_s,
          event_class: event.class.name,
          event_ancestry: Array(event.metadata.event_ancestry).compact.map(&:to_s)
        }
      end

      def _symbolize(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key.respond_to?(:to_sym) ? key.to_sym : key] = _deep_copy(value)
        end
      end

      def _deep_copy(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, nested), result| result[key] = _deep_copy(nested) }
        when Array
          value.map { |nested| _deep_copy(nested) }
        else
          value
        end
      end

      def _fetch(hash, key)
        hash[key] || hash[key.to_s]
      end

      def _format_frame(frame)
        case frame[:type]
        when :actor
          return nil unless frame[:actor_type]

          frame[:id] ? "#{frame[:actor_type]}:#{frame[:id]}" : frame[:actor_type]
        when :operation
          name = frame[:class] || "Operation"
          id = _display_id(frame[:id])
          id ? "#{name}(#{id})" : name
        when :handler
          event_class = frame[:event_class] || "Event"
          handler_name = frame[:class] || "Handler"
          id = _display_id(frame[:id])
          id ? "[#{event_class}] #{handler_name}(#{id})" : "[#{event_class}] #{handler_name}"
        end
      end

      def _display_id(id)
        return nil unless id

        prefix, suffix = id.split("_", 2)
        return id[0, 10] unless suffix

        "#{prefix}_#{suffix[0, 7]}"
      end
    end
  end
end
