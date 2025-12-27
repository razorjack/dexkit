# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dexkit"

require "minitest/autorun"

require 'dry/types'
module Types
  include Dry.Types(default: :nominal)
end
