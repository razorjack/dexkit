# frozen_string_literal: true

require "test_helper"

class TestMyOperation < Dex::Operation
  params do
    attribute :name, Types::String
  end

  def perform
    puts "Welome #{name}"
  end
end

class TestOperationParams < Minitest::Test
  def setup
    setup_test_database
  end

  def test_parameters_and_perform
    op = operation(params: { name: Types::String, spy: Types::Any }) do
      spy.puts name
    end

    logger = Minitest::Mock.new
    logger.expect :puts, nil, ["Test test"]

    op.new(name: "Test test", spy: logger).call
    assert_mock logger
  end
end
