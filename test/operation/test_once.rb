# frozen_string_literal: true

require "test_helper"

class TestOperationOnce < Minitest::Test
  def setup
    setup_test_database
  end

  # --- DSL validation ---

  def test_once_dsl_validation
    assert_raises(ArgumentError, /once requires record to be enabled/) do
      define_operation(:TestOnceRecordDisabled) {
        record false
        once
      }
    end

    assert_raises(ArgumentError, /unknown prop/) do
      define_operation(:TestOnceUnknownProp) {
        prop :order_id, Integer
        once :bogus
      }
    end

    assert_raises(ArgumentError, /once can only be declared once/) do
      define_operation(:TestOnceDuplicate) {
        prop :order_id, Integer
        once :order_id
        once :order_id
      }
    end

    assert_raises(ArgumentError, /either prop names or a block/) do
      define_operation(:TestOncePropsAndBlock) {
        prop :order_id, Integer
        once(:order_id) { "key" }
      }
    end

    assert_raises(ArgumentError, /expires_in must be a duration/) do
      define_operation(:TestOnceInvalidExpiry) {
        prop :order_id, Integer
        once :order_id, expires_in: "bad"
      }
    end

    assert_raises(ArgumentError, /once requires result recording/) do
      define_operation(:TestOnceResultFalse) {
        prop :order_id, Integer
        record result: false
        once :order_id
      }
    end
  end

  # --- Key derivation ---

  def test_once_key_derivation
    # Single prop
    op1 = define_operation(:TestOnceKey) do
      prop :order_id, Integer
      once :order_id
    end
    assert_equal "TestOnceKey/order_id=123", op1._once_build_scoped_key(order_id: 123)

    # Composite key sorted alphabetically
    op2 = define_operation(:TestOnceComposite) do
      prop :merchant_id, Integer
      prop :plan_id, Integer
      once :merchant_id, :plan_id
    end
    assert_equal "TestOnceComposite/merchant_id=456/plan_id=789",
      op2._once_build_scoped_key(merchant_id: 456, plan_id: 789)

    # Escapes special characters (different inputs produce different keys)
    op3 = define_operation(:TestOnceEscape) do
      prop :a, String
      prop :b, String
      once :a, :b
    end
    key1 = op3._once_build_scoped_key(a: "1", b: "2/b=3")
    key2 = op3._once_build_scoped_key(a: "1/b=2", b: "3")
    refute_equal key1, key2
  end

  # --- Basic idempotency ---

  def test_once_idempotency
    with_recording do
      counter = []
      op = define_operation(:TestOnceIdempotent) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) do
          counter << 1
          "done"
        end
      end

      result1 = op.call(order_id: 1)
      assert_equal "done", result1
      assert_equal [1], counter
      assert_equal 1, OperationRecord.count
      record = OperationRecord.last
      assert_equal "TestOnceIdempotent/order_id=1", record.once_key
      assert_equal "completed", record.status

      # Second call replays stored result
      result2 = op.call(order_id: 1)
      assert_equal "done", result2
      assert_equal [1], counter
      assert_equal 1, OperationRecord.count
    end
  end

  def test_different_keys_execute_independently
    with_recording do
      counter = []
      op = define_operation(:TestOnceDiffKeys) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) do
          counter << order_id
          "done-#{order_id}"
        end
      end

      r1 = op.call(order_id: 1)
      r2 = op.call(order_id: 2)

      assert_equal "done-1", r1
      assert_equal "done-2", r2
      assert_equal [1, 2], counter
      assert_equal 2, OperationRecord.count
    end
  end

  # --- Bare once (all props) ---

  def test_bare_once_uses_all_props
    with_recording do
      counter = []
      op = define_operation(:TestOnceBare) do
        prop :source, String
        prop :external_id, String
        once
        define_method(:perform) do
          counter << 1
          "imported"
        end
      end

      op.call(source: "csv", external_id: "abc")
      op.call(source: "csv", external_id: "abc")
      op.call(source: "csv", external_id: "def")

      assert_equal [1, 1], counter
      assert_equal 2, OperationRecord.count
    end
  end

  # --- Block-based key ---

  def test_block_based_key
    with_recording do
      counter = []
      op = define_operation(:TestOnceBlock) do
        prop :order_id, Integer
        once { "payment-#{order_id}" }
        define_method(:perform) do
          counter << 1
          "charged"
        end
      end

      op.call(order_id: 1)
      op.call(order_id: 1)

      assert_equal [1], counter
      record = OperationRecord.last
      assert_equal "payment-1", record.once_key
    end
  end

  def test_block_key_nil_raises
    with_recording do
      op = define_operation(:TestOnceBlockNil) do
        prop :order_id, Integer
        once { nil }
        define_method(:perform) { "ok" }
      end

      assert_raises(RuntimeError, /once key must not be nil/) do
        op.call(order_id: 1)
      end
    end
  end

  # --- Call-site key (.once("key")) ---

  def test_call_site_key_overrides_class_level
    with_recording do
      counter = []
      op = define_operation(:TestOnceCallSite) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) do
          counter << 1
          "done"
        end
      end

      op.new(order_id: 1).once("custom-key").call
      op.new(order_id: 1).once("custom-key").call

      assert_equal [1], counter
      assert_equal "custom-key", OperationRecord.last.once_key
    end
  end

  def test_call_site_key_without_class_level_once
    with_recording do
      counter = []
      op = define_operation(:TestOnceCallSiteOnly) do
        prop :payload, String
        define_method(:perform) do
          counter << 1
          "processed"
        end
      end

      op.new(payload: "data").once("webhook-123").call
      op.new(payload: "data").once("webhook-123").call

      assert_equal [1], counter
    end
  end

  def test_call_site_nil_bypasses_once
    with_recording do
      counter = []
      op = define_operation(:TestOnceBypass) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) do
          counter << 1
          "done"
        end
      end

      op.call(order_id: 1)
      op.new(order_id: 1).once(nil).call

      assert_equal [1, 1], counter
    end
  end

  # --- Error replay ---

  def test_business_error_replayed
    with_recording do
      counter = []
      op = define_operation(:TestOnceErrorReplay) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) do
          counter << 1
          error!(:not_found, "Order not found")
        end
      end

      err1 = assert_raises(Dex::Error) { op.call(order_id: 1) }
      err2 = assert_raises(Dex::Error) { op.call(order_id: 1) }

      assert_equal :not_found, err1.code
      assert_equal :not_found, err2.code
      assert_equal "Order not found", err2.message
      assert_equal [1], counter
    end
  end

  def test_business_error_with_details_replayed
    with_recording do
      op = define_operation(:TestOnceErrorDetailsReplay) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) do
          error!(:validation_failed, "bad", details: { field: "amount" })
        end
      end

      assert_raises(Dex::Error) { op.call(order_id: 1) }
      err = assert_raises(Dex::Error) { op.call(order_id: 1) }

      assert_equal :validation_failed, err.code
      assert_equal({ "field" => "amount" }, err.details)
    end
  end

  # --- Exception does NOT consume key ---

  def test_exception_does_not_consume_key
    with_recording do
      call_count = 0
      op = define_operation(:TestOnceException) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) do
          call_count += 1
          raise "boom" if call_count == 1
          "recovered"
        end
      end

      assert_raises(RuntimeError) { op.call(order_id: 1) }

      # once_key should be cleared on the failed record
      failed_record = OperationRecord.last
      assert_equal "failed", failed_record.status
      assert_nil failed_record.once_key

      # Second call should execute (key was released)
      result = op.call(order_id: 1)
      assert_equal "recovered", result
      assert_equal 2, call_count
    end
  end

  # --- Expiry ---

  def test_expires_in_sets_expiry_on_record
    with_recording do
      op = define_operation(:TestOnceExpiry) do
        prop :user_id, Integer
        once :user_id, expires_in: 3600
        define_method(:perform) { "sent" }
      end

      op.call(user_id: 1)

      record = OperationRecord.last
      refute_nil record.once_key_expires_at
      assert_in_delta Time.now + 3600, record.once_key_expires_at, 5
    end
  end

  def test_expired_key_allows_re_execution
    with_recording do
      counter = []
      op = define_operation(:TestOnceExpired) do
        prop :user_id, Integer
        once :user_id, expires_in: 3600
        define_method(:perform) do
          counter << 1
          "sent"
        end
      end

      op.call(user_id: 1)

      # Manually expire the record
      record = OperationRecord.last
      record.update!(once_key_expires_at: Time.now - 1)

      op.call(user_id: 1)

      assert_equal [1, 1], counter
      assert_equal 2, OperationRecord.count
      # Old record should have once_key cleared
      old_record = OperationRecord.find(record.id)
      assert_nil old_record.once_key
    end
  end

  # --- clear_once! ---

  def test_clear_once_with_various_key_types
    with_recording do
      # Props-based key
      op1 = define_operation(:TestOnceClear) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { "done" }
      end

      op1.call(order_id: 1)
      assert_equal 1, OperationRecord.where.not(once_key: nil).count

      op1.clear_once!(order_id: 1)
      record = OperationRecord.last
      assert_nil record.once_key
      assert_equal "completed", record.status

      # Re-execution after clear
      op1.call(order_id: 1)
      assert_equal 2, OperationRecord.count

      # String-based key
      op2 = define_operation(:TestOnceClearString) do
        prop :payload, String
        define_method(:perform) { "processed" }
      end

      op2.new(payload: "data").once("webhook-123").call
      op2.clear_once!("webhook-123")
      assert_nil OperationRecord.where(name: "TestOnceClearString").last.once_key
    end
  end

  def test_clear_once_validation_and_idempotency
    # Raises without arguments
    op = define_operation(:TestOnceClearNoArgs) do
      prop :order_id, Integer
      once :order_id
    end

    assert_raises(ArgumentError, /pass a String key/) do
      op.clear_once!
    end

    # Clearing a non-existent key is a no-op
    with_recording do
      op2 = define_operation(:TestOnceClearIdempotent) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { "done" }
      end
      op2.clear_once!(order_id: 999)
    end
  end

  # --- Typed result replay ---

  def test_result_replay_various_types
    with_recording do
      # BigDecimal
      require "bigdecimal"
      op1 = define_operation(:TestOnceTypedReplay) do
        prop :order_id, Integer
        success BigDecimal
        once :order_id
        define_method(:perform) { BigDecimal("99.99") }
      end
      r1 = op1.call(order_id: 1)
      r2 = op1.call(order_id: 1)
      assert_instance_of BigDecimal, r1
      assert_instance_of BigDecimal, r2
      assert_equal BigDecimal("99.99"), r2

      # Hash
      op2 = define_operation(:TestOnceHashReplay) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { { status: "charged", amount: 42 } }
      end
      op2.call(order_id: 1)
      r3 = op2.call(order_id: 1)
      assert_equal({ "status" => "charged", "amount" => 42 }, r3)

      # Hash with :value key preserved
      op3 = define_operation(:TestOnceValueKeyHash) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { { value: 7 } }
      end
      r4 = op3.call(order_id: 1)
      r5 = op3.call(order_id: 1)
      assert_equal({ value: 7 }, r4)
      assert_equal({ "value" => 7 }, r5)

      # Primitive
      op4 = define_operation(:TestOncePrimitiveReplay) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { 42 }
      end
      r6 = op4.call(order_id: 1)
      r7 = op4.call(order_id: 1)
      assert_equal 42, r6
      assert_equal 42, r7

      # Nil
      op5 = define_operation(:TestOnceNilReplay) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { nil }
      end
      r8 = op5.call(order_id: 1)
      r9 = op5.call(order_id: 1)
      assert_nil r8
      assert_nil r9
    end
  end

  # --- Safe proxy interaction ---

  def test_safe_call_replays_ok_and_err
    with_recording do
      # Ok replay
      op1 = define_operation(:TestOnceSafeOk) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { "done" }
      end

      r1 = op1.new(order_id: 1).safe.call
      r2 = op1.new(order_id: 1).safe.call
      assert_instance_of Dex::Ok, r1
      assert_instance_of Dex::Ok, r2
      assert_equal "done", r2.value

      # Err replay
      op2 = define_operation(:TestOnceSafeErr) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { error!(:denied, "nope") }
      end

      r3 = op2.new(order_id: 1).safe.call
      r4 = op2.new(order_id: 1).safe.call
      assert_instance_of Dex::Err, r3
      assert_instance_of Dex::Err, r4
      assert_equal :denied, r4.error.code
    end
  end

  # --- Backend validation ---

  def test_once_backend_validation
    # No backend configured
    op1 = define_operation(:TestOnceNoBackend) do
      prop :order_id, Integer
      once :order_id
      define_method(:perform) { "done" }
    end
    assert_raises(RuntimeError, /once requires a record backend/) do
      op1.call(order_id: 1)
    end

    # Missing once_key column
    with_recording(record_class: MinimalOperationRecord) do
      op2 = define_operation(:TestOnceNoColumn) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { "done" }
      end
      error = assert_raises(ArgumentError) { op2.call(order_id: 1) }
      assert_match(/missing required attributes/, error.message)
      assert_match(/once_key/, error.message)
    end

    # Missing expiry column
    with_recording(record_class: OnceNoExpiryRecord) do
      op3 = define_operation(:TestOnceNoExpiryCol) do
        prop :user_id, Integer
        once :user_id, expires_in: 3600
        define_method(:perform) { "done" }
      end
      error = assert_raises(ArgumentError) { op3.call(user_id: 1) }
      assert_match(/missing required attributes/, error.message)
      assert_match(/once_key_expires_at/, error.message)
    end
  end

  # --- Chaining ---

  def test_once_returns_self_for_chaining
    with_recording do
      op = define_operation(:TestOnceChaining) do
        prop :order_id, Integer
        define_method(:perform) { "done" }
      end

      instance = op.new(order_id: 1)
      assert_same instance, instance.once("key")
    end
  end

  # --- Claim cleanup on inner pipeline failure ---

  def test_claim_released_on_inner_pipeline_exception
    with_recording do
      op = define_operation(:TestOnceClaimCleanup) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { raise "inner failure" }
      end

      assert_raises(RuntimeError) { op.call(order_id: 1) }

      # The claim should have been released — once_key cleared, not blocking future calls
      record = OperationRecord.last
      assert_nil record.once_key
      assert_nil OperationRecord.find_by(once_key: "TestOnceClaimCleanup/order_id=1")
    end
  end

  # --- Duplicate async record finalization ---

  def test_replay_finalizes_pending_record
    with_recording do
      op = define_operation(:TestOnceFinalize) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { "first" }
      end

      # First call executes normally
      op.call(order_id: 1)
      assert_equal 1, OperationRecord.count

      # Simulate an async duplicate: create a pending record, set it as the instance's record
      pending = OperationRecord.create!(name: "TestOnceFinalize", status: "running")
      instance = op.new(order_id: 1)
      instance.instance_variable_set(:@_dex_record_id, pending.id.to_s)

      result = instance.call

      assert_equal "first", result
      pending.reload
      assert_equal "completed", pending.status
      refute_nil pending.performed_at
      assert_equal({ "_dex_value" => "first" }, pending.result)
    end
  end

  def test_error_replay_finalizes_pending_record
    with_recording do
      op = define_operation(:TestOnceFinalizeErr) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) { error!(:denied, "nope", details: { reason: "blocked" }) }
      end

      assert_raises(Dex::Error) { op.call(order_id: 1) }

      # Simulate async duplicate
      pending = OperationRecord.create!(name: "TestOnceFinalizeErr", status: "running")
      instance = op.new(order_id: 1)
      instance.instance_variable_set(:@_dex_record_id, pending.id.to_s)

      assert_raises(Dex::Error) { instance.call }

      pending.reload
      assert_equal "error", pending.status
      assert_equal "denied", pending.error_code
      assert_equal "nope", pending.error_message
      assert_equal({ "reason" => "blocked" }, pending.error_details)
    end
  end

  def test_once_is_reserved_prop_name
    assert_raises(ArgumentError, /reserved/) do
      define_operation(:TestOncePropCollision) do
        prop :once, Integer
      end
    end
  end

  # --- Inheritance ---

  def test_once_inherited_by_subclass
    with_recording do
      counter = []
      parent = define_operation(:TestOnceParent) do
        prop :order_id, Integer
        once :order_id
        define_method(:perform) do
          counter << 1
          "parent"
        end
      end

      child = define_operation(:TestOnceChild, parent: parent)

      child.call(order_id: 1)
      child.call(order_id: 1)

      assert_equal [1], counter
    end
  end
end
