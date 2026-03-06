# frozen_string_literal: true

module Dex
  module Settings
    module ClassMethods
      def set(key, **options)
        @_settings ||= {}
        @_settings[key] = (@_settings[key] || {}).merge(options)
      end

      def validate_options!(options, known, dsl_name)
        unknown = options.keys - known
        return if unknown.empty?

        raise ArgumentError,
          "unknown #{dsl_name} option(s): #{unknown.map(&:inspect).join(", ")}. " \
          "Known: #{known.map(&:inspect).join(", ")}"
      end

      def settings_for(key)
        parent_settings = if superclass.respond_to?(:settings_for)
          superclass.settings_for(key) || {}
        else
          {}
        end
        own_settings = @_settings&.dig(key) || {}
        parent_settings.merge(own_settings)
      end
    end

    extend Dex::Concern
  end
end
