# frozen_string_literal: true

module FormHelpers
  def teardown
    _cleanup_form_constants
    super
  end

  def define_form(name, parent: Dex::Form, &block)
    form_class = Class.new(parent, &block)
    Object.const_set(name, form_class)
    _tracked_form_constants << name
    form_class
  end

  def build_form(parent: Dex::Form, &block)
    Class.new(parent, &block)
  end

  private

  def _tracked_form_constants
    @_tracked_form_constants ||= []
  end

  def _cleanup_form_constants
    return unless defined?(@_tracked_form_constants)

    @_tracked_form_constants.each do |const_name|
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
    end
    @_tracked_form_constants.clear
  end
end
