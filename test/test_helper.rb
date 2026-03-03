# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "dexkit"

require "minitest/autorun"

require "active_job"
require "active_job/test_helper"
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = nil

require "active_record"
ActiveRecord::Base.logger = nil

# Load test support files
require_relative "support/operation_helpers"
require_relative "support/database_helpers"
require_relative "support/event_helpers"
require_relative "support/form_helpers"

# Include helpers in all test cases
class Minitest::Test
  include OperationHelpers
  include DatabaseHelpers
  include EventHelpers
  include FormHelpers
end
