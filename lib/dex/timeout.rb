# frozen_string_literal: true

module Dex
  class Timeout < StandardError
    attr_reader :timeout, :ticket_id, :operation_name

    def initialize(timeout:, ticket_id:, operation_name:)
      @timeout = timeout.to_f
      @ticket_id = ticket_id
      @operation_name = operation_name
      super("#{operation_name} did not complete within #{@timeout}s (ticket: #{ticket_id})")
    end
  end
end
