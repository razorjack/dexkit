# frozen_string_literal: true

module FormHelpers
  include TemporaryConstants

  def teardown
    _cleanup_tracked_constants(:form)
    super
  end

  def define_form(name, parent: Dex::Form, &block)
    _track_constant(:form, name, Class.new(parent, &block))
  end

  def build_form(parent: Dex::Form, &block)
    Class.new(parent, &block)
  end

  private
end
