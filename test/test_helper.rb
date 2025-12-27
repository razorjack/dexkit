# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dexkit"

require "minitest/autorun"

require "active_job"
require "active_job/test_helper"
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = nil

require 'dry/types'
module Types
  include Dry.Types(default: :nominal)
end
