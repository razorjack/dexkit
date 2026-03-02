# frozen_string_literal: true

module EventHelpers
  def teardown
    _cleanup_event_constants
    Dex::Event::Bus.clear!
    Dex::Event::Trace.clear!
    Dex::Event::Suppression.clear!
    super
  end

  def define_event(name, &block)
    event_class = Class.new(Dex::Event, &block)
    Object.const_set(name, event_class)
    _tracked_event_constants << name
    event_class
  end

  def build_event(&block)
    Class.new(Dex::Event, &block)
  end

  def define_handler(name, &block)
    handler_class = Class.new(Dex::Event::Handler, &block)
    Object.const_set(name, handler_class)
    _tracked_event_constants << name
    handler_class
  end

  def build_handler(&block)
    Class.new(Dex::Event::Handler, &block)
  end

  def build_event_metadata(overrides = {})
    {
      "id" => SecureRandom.uuid,
      "timestamp" => Time.now.utc.iso8601(6),
      "trace_id" => SecureRandom.uuid
    }.merge(overrides)
  end

  private

  def _tracked_event_constants
    @_tracked_event_constants ||= []
  end

  def _cleanup_event_constants
    return unless defined?(@_tracked_event_constants)

    @_tracked_event_constants.each do |const_name|
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
    end
    @_tracked_event_constants.clear
  end
end
