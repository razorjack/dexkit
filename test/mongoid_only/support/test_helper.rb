# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)
require "dexkit"

require "minitest/autorun"

require "active_job"
require "active_job/test_helper"
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = nil

Warning.singleton_class.prepend(Module.new do
  def warn(message, **)
    return if message.include?("/mongoid-") || message.include?("/mongo-")

    super
  end
end)
original_verbose = $VERBOSE
$VERBOSE = nil
require "mongoid"
$VERBOSE = original_verbose

require_relative "../../support/temporary_constants"
require_relative "../../support/operation_helpers"
require_relative "../../support/event_helpers"
require_relative "../../support/form_helpers"
require_relative "../../support/mongoid_helpers"

class Minitest::Test
  include ActiveJob::TestHelper
  include OperationHelpers
  include EventHelpers
  include FormHelpers
  include MongoidHelpers
end
