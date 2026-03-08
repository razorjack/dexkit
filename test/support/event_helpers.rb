# frozen_string_literal: true

module EventHelpers
  include TemporaryConstants

  def teardown
    _deregister_tracked(:event, Dex::Event, Dex::Event::Handler)
    _cleanup_tracked_constants(:event)
    Dex::Event::Bus.clear!
    Dex::Event::Trace.clear!
    Dex::Event::Suppression.clear!
    super
  end

  def define_event(name, &block)
    _track_constant(:event, name, Class.new(Dex::Event, &block))
  end

  def build_event(&block)
    Class.new(Dex::Event, &block)
  end

  def define_handler(name, &block)
    _track_constant(:event, name, Class.new(Dex::Event::Handler, &block))
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
end
