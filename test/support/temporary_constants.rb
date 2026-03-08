# frozen_string_literal: true

module TemporaryConstants
  private

  def _track_constant(bucket, name, value)
    Object.const_set(name, value)
    _tracked_constants[bucket] << name
    value
  end

  def _cleanup_tracked_constants(bucket)
    return unless defined?(@_tracked_constants)

    _tracked_constants[bucket].each do |const_name|
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
    end
    _tracked_constants[bucket].clear
  end

  def _tracked_constants
    @_tracked_constants ||= Hash.new { |hash, key| hash[key] = [] }
  end
end
