# frozen_string_literal: true

module Dex
  module Concern
    def included(base)
      base.extend(self::ClassMethods) if const_defined?(:ClassMethods, false)
      super
    end
  end
end
