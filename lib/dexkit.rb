# frozen_string_literal: true

require "zeitwerk"

require "dry/types"
require "dry/struct"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/dex")
loader.setup

require_relative "dex/version"
require_relative "dex/parameters"
require_relative "dex/operation"
