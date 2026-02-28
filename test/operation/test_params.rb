# frozen_string_literal: true

require "test_helper"

class TestOperationParams < Minitest::Test
  def setup
    setup_test_database
  end

  def test_parameters_and_perform
    op = operation(params: { name: String, spy: Object }) do
      spy.puts name
    end

    logger = Minitest::Mock.new
    logger.expect :puts, nil, ["Test test"]

    op.new(name: "Test test", spy: logger).call
    assert_mock logger
  end

  def test_required_params_raise_when_missing
    op = operation(params: { name: String }) do
      name
    end

    assert_raises(ArgumentError) { op.new }
  end
end
