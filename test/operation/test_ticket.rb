# frozen_string_literal: true

require "test_helper"

class TestOperationTicket < Minitest::Test
  include ActiveJob::TestHelper

  def setup
    setup_test_database
  end

  # --- Construction ---

  def test_new_with_record_and_job
    with_recording do
      record = create_record(status: "pending")
      job = Object.new
      ticket = Dex::Operation::Ticket.new(record: record, job: job)

      assert_equal record, ticket.record
      assert_equal job, ticket.job
    end
  end

  def test_new_without_record
    job = Object.new
    ticket = Dex::Operation::Ticket.new(record: nil, job: job)

    assert_nil ticket.record
    assert_equal job, ticket.job
  end

  def test_from_record
    with_recording do
      record = create_record(status: "completed")
      ticket = Dex::Operation::Ticket.from_record(record)

      assert_equal record, ticket.record
      assert_nil ticket.job
    end
  end

  def test_from_record_raises_on_nil
    error = assert_raises(ArgumentError) { Dex::Operation::Ticket.from_record(nil) }
    assert_match(/from_record requires a record/, error.message)
  end

  # --- Delegated accessors ---

  def test_delegated_accessors
    with_recording do
      record = create_record(
        status: "error",
        name: "Orders::Place",
        error_code: "out_of_stock",
        error_message: "Item unavailable",
        error_details: { "item_id" => "123" }
      )
      ticket = Dex::Operation::Ticket.from_record(record)

      assert_equal record.id, ticket.id
      assert_equal "Orders::Place", ticket.operation_name
      assert_equal "error", ticket.status
      assert_equal "out_of_stock", ticket.error_code
      assert_equal "Item unavailable", ticket.error_message
      assert_equal({ "item_id" => "123" }, ticket.error_details)
    end
  end

  def test_delegated_accessors_raise_without_record
    ticket = Dex::Operation::Ticket.new(record: nil, job: nil)

    %i[id operation_name status error_code error_message error_details].each do |method|
      error = assert_raises(ArgumentError) { ticket.send(method) }
      assert_match(/requires a recorded operation/, error.message)
    end
  end

  # --- Predicates ---

  def test_status_predicates
    with_recording do
      completed = ticket_with_status("completed")
      assert completed.completed?
      refute completed.pending?
      refute completed.error?
      refute completed.failed?
      refute completed.running?
      assert completed.terminal?

      error = ticket_with_status("error", error_code: "bad")
      assert error.error?
      refute error.completed?
      assert error.terminal?

      failed = ticket_with_status("failed", error_code: "RuntimeError")
      assert failed.failed?
      refute failed.completed?
      assert failed.terminal?

      pending = ticket_with_status("pending")
      assert pending.pending?
      refute pending.terminal?

      running = ticket_with_status("running")
      assert running.running?
      refute running.terminal?
    end
  end

  def test_recorded_predicate
    with_recording do
      assert Dex::Operation::Ticket.new(record: create_record(status: "pending"), job: nil).recorded?
    end
    refute Dex::Operation::Ticket.new(record: nil, job: nil).recorded?
  end

  # --- Reload ---

  def test_reload_refreshes_record_from_db
    with_recording do
      record = create_record(status: "pending")
      ticket = Dex::Operation::Ticket.from_record(record)

      assert_equal "pending", ticket.status

      record.update!(status: "completed", performed_at: Time.now)
      ticket.reload

      assert_equal "completed", ticket.status
    end
  end

  def test_reload_returns_self_for_chaining
    with_recording do
      record = create_record(status: "completed")
      ticket = Dex::Operation::Ticket.from_record(record)

      assert_equal ticket, ticket.reload
    end
  end

  def test_reload_raises_without_record
    ticket = Dex::Operation::Ticket.new(record: nil, job: nil)
    error = assert_raises(ArgumentError) { ticket.reload }
    assert_match(/requires a recorded operation/, error.message)
  end

  # --- Outcome reconstruction ---

  def test_outcome_completed
    with_recording do
      # Hash result — symbolized keys
      hash_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: { "url" => "/done", "count" => 42 })
      )
      result = hash_ticket.outcome
      assert_instance_of Dex::Ok, result
      assert_equal({ url: "/done", count: 42 }, result.value)

      # Nested keys — deep symbolization
      nested_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: {
          "order" => { "id" => 1, "items" => [{ "name" => "Widget" }] }
        })
      )
      assert_equal({ order: { id: 1, items: [{ name: "Widget" }] } }, nested_ticket.outcome.value)

      # _dex_value unwrapping — string
      unwrap_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: { "_dex_value" => "hello" })
      )
      assert_equal "hello", unwrap_ticket.outcome.value

      # _dex_value unwrapping — non-hash value
      int_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: { "_dex_value" => 42 })
      )
      assert_equal 42, int_ticket.outcome.value

      # nil result
      nil_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: nil)
      )
      result = nil_ticket.outcome
      assert_instance_of Dex::Ok, result
      assert_nil result.value
    end
  end

  def test_outcome_error
    with_recording do
      # With details
      with_details = Dex::Operation::Ticket.from_record(
        create_record(
          status: "error",
          error_code: "out_of_stock",
          error_message: "Item unavailable",
          error_details: { "item_id" => "123" }
        )
      )
      result = with_details.outcome
      assert_instance_of Dex::Err, result
      assert_equal :out_of_stock, result.code
      assert_equal "Item unavailable", result.message
      assert_equal({ item_id: "123" }, result.details)

      # Without details
      without_details = Dex::Operation::Ticket.from_record(
        create_record(status: "error", error_code: "forbidden", error_message: "Access denied")
      )
      result = without_details.outcome
      assert_instance_of Dex::Err, result
      assert_equal :forbidden, result.code
      assert_nil result.details
    end
  end

  def test_outcome_returns_nil_for_non_terminal_and_failed
    with_recording do
      assert_nil Dex::Operation::Ticket.from_record(
        create_record(status: "failed", error_code: "RuntimeError", error_message: "boom")
      ).outcome

      assert_nil Dex::Operation::Ticket.from_record(
        create_record(status: "pending")
      ).outcome

      assert_nil Dex::Operation::Ticket.from_record(
        create_record(status: "running")
      ).outcome
    end
  end

  def test_outcome_raises_without_record
    ticket = Dex::Operation::Ticket.new(record: nil, job: nil)
    error = assert_raises(ArgumentError) { ticket.outcome }
    assert_match(/requires a recorded operation/, error.message)
  end

  def test_outcome_pattern_matching_ok
    with_recording do
      record = create_record(status: "completed", result: { "url" => "/orders/1" })
      ticket = Dex::Operation::Ticket.from_record(record)

      case ticket.outcome
      in Dex::Ok(url:)
        assert_equal "/orders/1", url
      else
        flunk "Pattern matching failed"
      end
    end
  end

  def test_outcome_pattern_matching_err
    with_recording do
      record = create_record(status: "error", error_code: "invalid", error_message: "Bad input")
      ticket = Dex::Operation::Ticket.from_record(record)

      case ticket.outcome
      in Dex::Err(code: :invalid, message:)
        assert_equal "Bad input", message
      else
        flunk "Pattern matching failed"
      end
    end
  end

  # --- Wait ---

  def test_wait_returns_ok_when_already_completed
    with_recording do
      record = create_record(status: "completed", result: { "url" => "/done" })
      ticket = Dex::Operation::Ticket.from_record(record)

      result = ticket.wait(1)
      assert_instance_of Dex::Ok, result
      assert_equal({ url: "/done" }, result.value)
    end
  end

  def test_wait_returns_err_when_already_error
    with_recording do
      record = create_record(status: "error", error_code: "invalid", error_message: "Bad")
      ticket = Dex::Operation::Ticket.from_record(record)

      result = ticket.wait(1)
      assert_instance_of Dex::Err, result
      assert_equal :invalid, result.code
    end
  end

  def test_wait_raises_operation_failed_when_failed
    with_recording do
      record = create_record(status: "failed", error_code: "RuntimeError", error_message: "boom")
      ticket = Dex::Operation::Ticket.from_record(record)

      error = assert_raises(Dex::OperationFailed) { ticket.wait(1) }
      assert_equal "TestOp", error.operation_name
      assert_equal "RuntimeError", error.exception_class
      assert_equal "boom", error.exception_message
    end
  end

  def test_wait_returns_nil_on_timeout
    with_recording do
      record = create_record(status: "pending")
      ticket = Dex::Operation::Ticket.from_record(record)

      result = ticket.wait(0.05, interval: 0.01)
      assert_nil result
    end
  end

  def test_wait_polls_until_complete
    with_recording do
      record = create_record(status: "pending")
      ticket = Dex::Operation::Ticket.from_record(record)

      poll_count = 0
      original_reload = ticket.method(:reload)
      ticket.define_singleton_method(:reload) do
        poll_count += 1
        if poll_count >= 2
          record.update!(status: "completed", result: { "value" => "done" }, performed_at: Time.now)
        end
        original_reload.call
      end

      result = ticket.wait(2, interval: 0.01)
      assert_instance_of Dex::Ok, result
      assert poll_count >= 2
    end
  end

  def test_wait_with_callable_interval
    with_recording do
      record = create_record(status: "completed", result: { "ok" => true })
      ticket = Dex::Operation::Ticket.from_record(record)

      intervals = []
      interval_fn = lambda { |n|
        intervals << n
        0.01
      }

      ticket.wait(1, interval: interval_fn)
      # Already terminal on first check — interval never called
      assert_empty intervals
    end
  end

  def test_wait_validation
    # No record
    unrecorded = Dex::Operation::Ticket.new(record: nil, job: nil)
    error = assert_raises(ArgumentError) { unrecorded.wait(1) }
    assert_match(/wait requires a recorded operation/, error.message)

    with_recording do
      ticket = Dex::Operation::Ticket.from_record(create_record(status: "pending"))

      # Timeout: zero, negative, wrong type
      assert_raises(ArgumentError) { ticket.wait(0) }
      assert_raises(ArgumentError) { ticket.wait(-1) }
      error = assert_raises(ArgumentError) { ticket.wait("five") }
      assert_match(/timeout must be a positive Numeric/, error.message)

      # Interval: zero, negative
      assert_raises(ArgumentError) { ticket.wait(1, interval: 0) }
      error = assert_raises(ArgumentError) { ticket.wait(1, interval: -0.1) }
      assert_match(/interval must be a positive number or a callable/, error.message)
    end
  end

  # --- Wait! ---

  def test_wait_bang_success
    with_recording do
      # Returns value
      ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: { "url" => "/done" })
      )
      assert_equal({ url: "/done" }, ticket.wait!(1))

      # Returns nil for nil result
      nil_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: nil)
      )
      assert_nil nil_ticket.wait!(1)
    end
  end

  def test_wait_bang_errors
    with_recording do
      # Business error → Dex::Error
      error_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "error", error_code: "out_of_stock", error_message: "Gone")
      )
      error = assert_raises(Dex::Error) { error_ticket.wait!(1) }
      assert_equal :out_of_stock, error.code
      assert_equal "Gone", error.message

      # Infrastructure crash → Dex::OperationFailed
      failed_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "failed", error_code: "NoMethodError", error_message: "undefined method 'foo'")
      )
      error = assert_raises(Dex::OperationFailed) { failed_ticket.wait!(1) }
      assert_equal "NoMethodError", error.exception_class

      # Timeout → Dex::Timeout
      pending_record = create_record(status: "pending")
      pending_ticket = Dex::Operation::Ticket.from_record(pending_record)
      error = assert_raises(Dex::Timeout) { pending_ticket.wait!(0.05, interval: 0.01) }
      assert_equal pending_record.id, error.ticket_id
      assert_equal "TestOp", error.operation_name
      assert_in_delta 0.05, error.timeout, 0.001
    end
  end

  # --- to_param ---

  def test_to_param_returns_id_as_string
    with_recording do
      record = create_record(status: "pending")
      ticket = Dex::Operation::Ticket.from_record(record)

      assert_equal record.id.to_s, ticket.to_param
    end
  end

  # --- as_json ---

  def test_as_json_by_status
    with_recording do
      # Completed — includes id, name, status, result
      completed_record = create_record(status: "completed", result: { "url" => "/orders/1" })
      json = Dex::Operation::Ticket.from_record(completed_record).as_json
      assert_equal completed_record.id.to_s, json["id"]
      assert_equal "TestOp", json["name"]
      assert_equal "completed", json["status"]
      assert_equal({ "url" => "/orders/1" }, json["result"])

      # Error — includes error hash
      error_record = create_record(
        status: "error",
        error_code: "out_of_stock",
        error_message: "Item unavailable",
        error_details: { "item_id" => "123" }
      )
      json = Dex::Operation::Ticket.from_record(error_record).as_json
      assert_equal "error", json["status"]
      assert_equal "out_of_stock", json.dig("error", "code")
      assert_equal "Item unavailable", json.dig("error", "message")
      assert_equal({ "item_id" => "123" }, json.dig("error", "details"))

      # Failed — redacts exception details
      json = Dex::Operation::Ticket.from_record(
        create_record(status: "failed", error_code: "RuntimeError", error_message: "boom")
      ).as_json
      assert_equal "failed", json["status"]
      refute json.key?("error")
      refute json.key?("result")

      # Pending — no error, no result
      json = Dex::Operation::Ticket.from_record(
        create_record(status: "pending")
      ).as_json
      assert_equal "pending", json["status"]
      refute json.key?("error")
      refute json.key?("result")
    end
  end

  def test_as_json_edge_cases
    with_recording do
      # Unwraps _dex_value
      json = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: { "_dex_value" => 42 })
      ).as_json
      assert_equal 42, json["result"]

      # Omits nil result
      json = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: nil)
      ).as_json
      refute json.key?("result")
    end
  end

  def test_as_json_raises_without_record
    ticket = Dex::Operation::Ticket.new(record: nil, job: nil)
    error = assert_raises(ArgumentError) { ticket.as_json }
    assert_match(/requires a recorded operation/, error.message)
  end

  # --- inspect ---

  def test_inspect_with_record
    with_recording do
      record = create_record(status: "pending")
      ticket = Dex::Operation::Ticket.from_record(record)

      assert_match(/Dex::Operation::Ticket TestOp/, ticket.inspect)
      assert_match(/id=/, ticket.inspect)
      assert_match(/status="pending"/, ticket.inspect)
    end
  end

  def test_inspect_without_record
    ticket = Dex::Operation::Ticket.new(record: nil, job: nil)
    assert_match(/\(unrecorded\)/, ticket.inspect)
  end

  # --- AsyncProxy integration ---

  def test_async_call_returns_ticket_with_record_strategy
    with_recording do
      op_class = define_operation(:TestAsyncTicketRecord) do
        prop :name, String
        def perform = nil
      end

      ticket = op_class.new(name: "Test").async.call
      assert_instance_of Dex::Operation::Ticket, ticket
      assert ticket.recorded?
      assert_equal "pending", ticket.status
      assert_equal "TestAsyncTicketRecord", ticket.operation_name
      refute_nil ticket.job
    end
  end

  def test_async_call_returns_ticket_with_direct_strategy
    op_class = define_operation(:TestAsyncTicketDirect) do
      record false
      prop :name, String
      def perform = nil
    end

    ticket = op_class.new(name: "Test").async.call
    assert_instance_of Dex::Operation::Ticket, ticket
    refute ticket.recorded?
    refute_nil ticket.job
  end

  def test_async_call_ticket_record_has_correct_params
    with_recording do
      op_class = define_operation(:TestAsyncTicketParams) do
        prop :name, String
        prop :count, Integer
        def perform = nil
      end

      ticket = op_class.new(name: "Alice", count: 5).async.call
      assert_equal({ "name" => "Alice", "count" => 5 }, ticket.record.params)
    end
  end

  # --- Full async round-trip with ticket ---

  def test_full_round_trip_success
    with_recording do
      op_class = define_operation(:TestTicketRoundTrip) do
        prop :name, String
        def perform = { greeting: "Hello #{name}" }
      end

      ticket = op_class.new(name: "World").async.call
      assert_equal "pending", ticket.status

      Dex::Operation::RecordJob.new.perform(
        class_name: "TestTicketRoundTrip",
        record_id: ticket.id
      )

      ticket.reload
      assert_equal "completed", ticket.status

      result = ticket.outcome
      assert_instance_of Dex::Ok, result
      assert_equal({ greeting: "Hello World" }, result.value)
    end
  end

  def test_full_round_trip_error
    with_recording do
      op_class = define_operation(:TestTicketRoundTripErr) do
        prop :name, String
        error :invalid
        def perform = error!(:invalid, "Bad input", details: { field: "name" })
      end

      ticket = op_class.new(name: "Test").async.call

      assert_raises(Dex::Error) do
        Dex::Operation::RecordJob.new.perform(
          class_name: "TestTicketRoundTripErr",
          record_id: ticket.id
        )
      end

      ticket.reload
      result = ticket.outcome
      assert_instance_of Dex::Err, result
      assert_equal :invalid, result.code
      assert_equal({ field: "name" }, result.details)
    end
  end

  def test_full_round_trip_failed
    with_recording do
      op_class = define_operation(:TestTicketRoundTripFail) do
        prop :name, String
        def perform = raise "infrastructure crash"
      end

      ticket = op_class.new(name: "Test").async.call

      assert_raises(RuntimeError) do
        Dex::Operation::RecordJob.new.perform(
          class_name: "TestTicketRoundTripFail",
          record_id: ticket.id
        )
      end

      ticket.reload
      assert ticket.failed?
      assert_nil ticket.outcome
    end
  end

  # --- Prescriptive errors ---

  def test_safe_proxy_async_raises_prescriptive_error
    op = build_operation { def perform = nil }.new
    error = assert_raises(NoMethodError) { op.safe.async }
    assert_match(/alternative execution strategies/, error.message)
    assert_match(/wait/, error.message)
  end

  def test_async_proxy_safe_raises_prescriptive_error
    op = build_operation { def perform = nil }.new
    error = assert_raises(NoMethodError) { op.async.safe }
    assert_match(/alternative execution strategies/, error.message)
    assert_match(/wait/, error.message)
  end

  # --- Outcome: typed result coercion ---

  def test_outcome_type_coercion
    with_recording do
      # Date coercion
      date_op = define_operation(:TestTicketTypedDate) do
        success Date
        prop :day, String
        def perform = Date.parse(day)
      end
      date_op.new(day: "2025-06-15").async.call
      record = OperationRecord.last
      Dex::Operation::RecordJob.new.perform(class_name: "TestTicketTypedDate", record_id: record.id)
      result = Dex::Operation::Ticket.from_record(record.reload).outcome
      assert_instance_of Date, result.value
      assert_equal Date.new(2025, 6, 15), result.value

      # Symbol coercion
      symbol_op = define_operation(:TestTicketTypedSymbol) do
        success Symbol
        prop :status, Symbol
        def perform = status
      end
      symbol_op.new(status: :active).async.call
      record = OperationRecord.last
      Dex::Operation::RecordJob.new.perform(class_name: "TestTicketTypedSymbol", record_id: record.id)
      result = Dex::Operation::Ticket.from_record(record.reload).outcome
      assert_instance_of Symbol, result.value
      assert_equal :active, result.value

      # Ref coercion (model lookup)
      model = TestModel.create!(name: "Alice")
      ref_op = define_operation(:TestTicketTypedRef) do
        success _Ref(TestModel)
        prop :model_id, Integer
        def perform = TestModel.find(model_id)
      end
      ref_op.new(model_id: model.id).async.call
      record = OperationRecord.last
      Dex::Operation::RecordJob.new.perform(class_name: "TestTicketTypedRef", record_id: record.id)
      result = Dex::Operation::Ticket.from_record(record.reload).outcome
      assert_instance_of TestModel, result.value
      assert_equal model.id, result.value.id
    end
  end

  def test_outcome_graceful_degradation_when_class_missing
    with_recording do
      record = create_record(
        name: "NonexistentClass::DoStuff",
        status: "completed",
        result: { "url" => "/done" }
      )
      ticket = Dex::Operation::Ticket.from_record(record)

      result = ticket.outcome
      assert_instance_of Dex::Ok, result
      assert_equal({ url: "/done" }, result.value)
    end
  end

  # --- Outcome: array symbolization ---

  def test_outcome_symbolizes_arrays
    with_recording do
      # Array of hashes via _dex_value
      array_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: { "_dex_value" => [{ "name" => "Alice" }, { "name" => "Bob" }] })
      )
      result = array_ticket.outcome
      assert_instance_of Dex::Ok, result
      assert_equal [{ name: "Alice" }, { name: "Bob" }], result.value

      # Nested array in hash
      nested_ticket = Dex::Operation::Ticket.from_record(
        create_record(status: "completed", result: { "items" => [{ "id" => 1 }, { "id" => 2 }] })
      )
      assert_equal({ items: [{ id: 1 }, { id: 2 }] }, nested_ticket.outcome.value)
    end
  end

  # --- Wait: Duration support ---

  def test_wait_accepts_active_support_duration
    with_recording do
      record = create_record(status: "completed", result: { "ok" => true })
      ticket = Dex::Operation::Ticket.from_record(record)

      assert_instance_of Dex::Ok, ticket.wait(3.seconds)
      assert_equal({ ok: true }, ticket.wait!(3.seconds))
    end
  end

  # --- Exception classes ---

  def test_operation_failed_exception
    refute Dex::OperationFailed < Dex::Error
    assert Dex::OperationFailed < StandardError

    error = Dex::OperationFailed.new(
      operation_name: "Orders::Place",
      exception_class: "RuntimeError",
      exception_message: "connection refused"
    )
    assert_equal "Orders::Place", error.operation_name
    assert_equal "RuntimeError", error.exception_class
    assert_equal "connection refused", error.exception_message
    assert_match(/Orders::Place failed with RuntimeError: connection refused/, error.message)
  end

  def test_timeout_exception
    refute Dex::Timeout < Dex::Error
    assert Dex::Timeout < StandardError

    error = Dex::Timeout.new(timeout: 3, ticket_id: "op_abc", operation_name: "Reports::Generate")
    assert_in_delta 3.0, error.timeout, 0.001
    assert_equal "op_abc", error.ticket_id
    assert_equal "Reports::Generate", error.operation_name
    assert_match(/Reports::Generate did not complete within 3\.0s/, error.message)
  end

  private

  def create_record(status:, name: "TestOp", **attrs)
    OperationRecord.create!(
      id: Dex::Id.generate("op_"),
      name: name,
      status: status,
      performed_at: status.in?(%w[completed error failed]) ? Time.now : nil,
      **attrs
    )
  end

  def ticket_with_status(status, **attrs)
    Dex::Operation::Ticket.from_record(create_record(status: status, **attrs))
  end
end
