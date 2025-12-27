# frozen_string_literal: true

require "zeitwerk"
require "dex/version"

require "dry/types"
require "dry/struct"

module Dex
  loader = Zeitwerk::Loader.for_gem
  loader.inflector.inflect(
    "dex" => "Dex"
  )
  loader.setup
end
