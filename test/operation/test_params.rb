# frozen_string_literal: true

require "test_helper"

class TestMyOperation < Dex::Operation
  params do
    attribute :name, Types::String
  end

  def perform
    puts "Welome #{params.name}"
  end
end

class TestOperationParams < Minitest::Test
  def setup
    setup_test_database
  end

  def test_parameters_and_perform
    op = Class.new(Dex::Operation) do
      params do
        attribute :name, Types::String
        attribute :spy, Types::Any
      end

      def perform
        params.spy.puts params.name
      end
    end

    logger = Minitest::Mock.new
    logger.expect :puts, nil, ["Test test"]

    op.new(name: "Test test", spy: logger).perform
    assert_mock logger
  end
end
