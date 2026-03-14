# frozen_string_literal: true

require "test_helper"

class TestOperationExplain < Minitest::Test
  def setup
    setup_test_database
  end

  # Basic shape

  def test_returns_frozen_hash
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert_instance_of Hash, info
    assert info.frozen?
  end

  def test_operation_name
    define_operation(:ExplainTest) { def perform = "ok" }
    info = ExplainTest.explain
    assert_equal "ExplainTest", info[:operation]
  end

  def test_anonymous_operation_name
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert_equal "(anonymous)", info[:operation]
  end

  def test_all_keys_present
    op = build_operation { def perform = "ok" }
    info = op.explain
    expected = %i[operation props context guards once lock record transaction rescue_from callbacks pipeline callable]
    assert_equal expected.sort, info.keys.sort
  end

  # Props

  def test_props_reported
    op = build_operation do
      prop :name, String
      prop :count, Integer
      def perform = "ok"
    end
    info = op.explain(name: "Alice", count: 5)
    assert_equal({ name: "Alice", count: 5 }, info[:props])
  end

  def test_props_empty_when_none_declared
    op = build_operation { def perform = "ok" }
    assert_equal({}, op.explain[:props])
  end

  def test_invalid_props_return_partial_explain
    op = build_operation do
      prop :name, String
      def perform = "ok"
    end
    info = op.explain(name: 123)
    assert info.key?(:error)
    assert_match(/Literal::TypeError/, info[:error])
    assert_equal({}, info[:props])
    refute info[:callable]
  end

  # Context

  def test_context_resolution_sources
    # Ambient source
    ambient_op = build_operation do
      prop :user, String
      context user: :current_user
      def perform = "ok"
    end
    Dex.with_context(current_user: "admin") do
      info = ambient_op.explain
      assert_equal({ user: :current_user }, info[:context][:mappings])
      assert_equal({ user: "admin" }, info[:context][:resolved])
      assert_equal({ user: :ambient }, info[:context][:source])

      # Explicit source (same op, explicit kwarg overrides ambient)
      info = ambient_op.explain(user: "explicit_user")
      assert_equal :explicit, info[:context][:source][:user]
      assert_equal "explicit_user", info[:context][:resolved][:user]
    end

    # Default source
    default_op = build_operation do
      prop :locale, String, default: "en"
      context :locale
      def perform = "ok"
    end
    info = default_op.explain
    assert_equal :default, info[:context][:source][:locale]
  end

  def test_context_empty_when_no_mappings
    op = build_operation do
      prop :name, String
      def perform = "ok"
    end
    info = op.explain(name: "test")
    assert_equal({}, info[:context][:resolved])
    assert_equal({}, info[:context][:mappings])
    assert_equal({}, info[:context][:source])
  end

  # Guards

  def test_guards_all_pass
    op = build_operation do
      prop :allowed, Literal::Types::BooleanType.new
      guard(:denied) { !allowed }
      def perform = "ok"
    end
    info = op.explain(allowed: true)
    assert info[:guards][:passed]
    assert_equal [{ name: :denied, passed: true }], info[:guards][:results]
    assert info[:callable]
  end

  def test_guards_failure
    # Default message
    op = build_operation do
      guard(:blocked) { true }
      def perform = "ok"
    end
    info = op.explain
    refute info[:guards][:passed]
    assert_equal [{ name: :blocked, passed: false, message: "blocked" }], info[:guards][:results]
    refute info[:callable]

    # Custom message
    op2 = build_operation do
      guard(:denied, "Access denied") { true }
      def perform = "ok"
    end
    info2 = op2.explain
    assert_equal "Access denied", info2[:guards][:results][0][:message]

    # Passed results have no message key
    op3 = build_operation do
      guard(:check) { false }
      def perform = "ok"
    end
    info3 = op3.explain
    refute info3[:guards][:results][0].key?(:message)
  end

  def test_guards_multiple_mixed
    op = build_operation do
      guard(:first) { true }
      guard(:second) { false }
      def perform = "ok"
    end
    info = op.explain
    refute info[:guards][:passed]
    assert_equal :first, info[:guards][:results][0][:name]
    refute info[:guards][:results][0][:passed]
    assert_equal :second, info[:guards][:results][1][:name]
    assert info[:guards][:results][1][:passed]
  end

  def test_guards_skipped_via_requires
    op = build_operation do
      guard(:prerequisite) { true }
      guard(:dependent, requires: :prerequisite) { true }
      def perform = "ok"
    end
    info = op.explain
    dependent = info[:guards][:results].find { |r| r[:name] == :dependent }
    refute dependent[:passed]
    assert dependent[:skipped]
  end

  def test_guards_empty_when_none_declared
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert info[:guards][:passed]
    assert_empty info[:guards][:results]
    assert info[:callable]
  end

  def test_guards_does_not_run_perform
    performed = false
    op = build_operation do
      define_method(:perform) { performed = true }
    end
    op.explain
    refute performed
  end

  def test_guards_does_not_trigger_callbacks
    called = false
    op = build_operation do
      before { called = true }
      def perform = "ok"
    end
    op.explain
    refute called
  end

  # Once

  def test_once_inactive_when_not_declared
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert_equal({ active: false }, info[:once])
  end

  def test_once_active_with_key
    op = build_operation do
      prop :order_id, Integer
      once :order_id
      def perform = "ok"
    end
    info = op.explain(order_id: 42)
    assert info[:once][:active]
    assert_includes info[:once][:key], "order_id=42"
    assert_nil info[:once][:expires_in]
  end

  def test_once_with_expires_in
    op = build_operation do
      prop :order_id, Integer
      once :order_id, expires_in: 3600
      def perform = "ok"
    end
    info = op.explain(order_id: 1)
    assert_equal 3600, info[:once][:expires_in]
  end

  def test_once_valid_statuses
    # :unavailable without backend
    unavailable_op = define_operation(:OnceExplainNoBackend) do
      prop :order_id, Integer
      once :order_id
      def perform = "ok"
    end
    info = unavailable_op.explain(order_id: 1)
    assert_equal :unavailable, info[:once][:status]

    with_recording do
      # :fresh — no prior execution
      fresh_op = define_operation(:OnceExplainFresh) do
        prop :order_id, Integer
        once :order_id
        def perform = "ok"
      end
      info = fresh_op.explain(order_id: 999)
      assert_equal :fresh, info[:once][:status]

      # :exists — after execution
      exists_op = define_operation(:OnceExplainExists) do
        prop :order_id, Integer
        once :order_id
        def perform = "ok"
      end
      exists_op.call(order_id: 77)
      info = exists_op.explain(order_id: 77)
      assert_equal :exists, info[:once][:status]

      # :expired — after expiry
      expired_op = define_operation(:OnceExplainExpired) do
        prop :order_id, Integer
        once :order_id, expires_in: 3600
        def perform = "ok"
      end
      expired_op.call(order_id: 55)
      key = expired_op._once_build_scoped_key(order_id: 55)
      OperationRecord.where(once_key: key).update_all(once_key_expires_at: Time.now - 7200)
      info = expired_op.explain(order_id: 55)
      assert_equal :expired, info[:once][:status]

      # :pending — record exists in pending state
      pending_op = define_operation(:OnceExplainPending) do
        prop :order_id, Integer
        once :order_id
        def perform = "ok"
      end
      key = pending_op._once_build_scoped_key(order_id: 88)
      OperationRecord.create!(name: "OnceExplainPending", once_key: key, status: "pending")
      info = pending_op.explain(order_id: 88)
      assert_equal :pending, info[:once][:status]
    end
  end

  # Lock

  def test_lock_inactive_when_not_declared
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert_equal({ active: false }, info[:lock])
  end

  def test_lock_active_with_string_key
    op = build_operation do
      advisory_lock "my_lock"
      def perform = "ok"
    end
    info = op.explain
    assert info[:lock][:active]
    assert_equal "my_lock", info[:lock][:key]
    assert_nil info[:lock][:timeout]
  end

  def test_lock_with_timeout
    op = build_operation do
      advisory_lock "my_lock", timeout: 5
      def perform = "ok"
    end
    info = op.explain
    assert_equal 5, info[:lock][:timeout]
  end

  def test_lock_with_proc_key
    op = build_operation do
      prop :order_id, Integer
      advisory_lock { "order:#{order_id}" }
      def perform = "ok"
    end
    info = op.explain(order_id: 7)
    assert_equal "order:7", info[:lock][:key]
  end

  # Record

  def test_record_enabled_by_default_with_backend
    op = define_operation(:RecordExplainEnabled) { def perform = "ok" }
    with_recording do
      info = op.explain
      assert info[:record][:enabled]
      assert info[:record][:params]
      assert info[:record][:result]
    end
  end

  def test_record_disabled_without_backend
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert_equal({ enabled: false }, info[:record])
  end

  def test_record_disabled_explicitly
    op = define_operation(:RecordExplainDisabled) do
      record false
      def perform = "ok"
    end
    with_recording do
      info = op.explain
      assert_equal({ enabled: false }, info[:record])
    end
  end

  def test_record_params_and_result_flags
    op = define_operation(:RecordExplainFlags) do
      record params: false, result: false
      def perform = "ok"
    end
    with_recording do
      info = op.explain
      assert info[:record][:enabled]
      refute info[:record][:params]
      refute info[:record][:result]
    end
  end

  def test_record_reports_misconfigured_backend
    op = define_operation(:RecordExplainMisconfigured) { def perform = "ok" }

    with_recording(record_class: MinimalOperationRecord) do
      info = op.explain

      assert info[:record][:enabled]
      assert_equal :misconfigured, info[:record][:status]
      assert_includes info[:record][:missing_fields], "status"
      refute info[:callable]
    end
  end

  # Transaction

  def test_transaction_enabled_by_default
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert info[:transaction][:enabled]
  end

  def test_transaction_disabled
    op = build_operation do
      transaction false
      def perform = "ok"
    end
    info = op.explain
    refute info[:transaction][:enabled]
  end

  # Rescue

  def test_rescue_empty_when_none_declared
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert_equal({}, info[:rescue_from])
  end

  def test_rescue_mappings
    op = build_operation do
      rescue_from ArgumentError, as: :bad_input
      rescue_from RuntimeError, as: :runtime_failure
      def perform = "ok"
    end
    info = op.explain
    assert_equal :bad_input, info[:rescue_from]["ArgumentError"]
    assert_equal :runtime_failure, info[:rescue_from]["RuntimeError"]
  end

  # Callbacks

  def test_callbacks_zero_when_none_declared
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert_equal({ before: 0, after: 0, around: 0 }, info[:callbacks])
  end

  def test_callbacks_counted
    op = build_operation do
      before {}
      before {}
      after {}
      around { |&blk| blk.call }
      def perform = "ok"
    end
    info = op.explain
    assert_equal 2, info[:callbacks][:before]
    assert_equal 1, info[:callbacks][:after]
    assert_equal 1, info[:callbacks][:around]
  end

  # Pipeline

  def test_pipeline_steps
    op = build_operation { def perform = "ok" }
    info = op.explain
    assert_equal %i[trace result guard once lock record transaction rescue callback], info[:pipeline]
  end

  # Callable

  def test_callable_matches_callable_bool
    op = build_operation do
      guard(:check) { true }
      def perform = "ok"
    end
    info = op.explain
    assert_equal op.callable?, info[:callable]
  end

  # Custom middleware

  def test_custom_middleware_explain_hook
    class_methods = Module.new do
      def _rate_limit_explain(instance, info)
        info[:rate_limit] = { key: "custom", max: 100 }
      end
    end

    wrapper = Module.new do
      define_singleton_method(:name) { "RateLimitWrapper" }

      define_method(:included) do |base|
        base.extend(class_methods)
        super(base)
      end
      module_function :included

      define_method(:_rate_limit_wrap) { yield }
    end

    op = build_operation do
      use wrapper
      def perform = "ok"
    end
    info = op.explain
    assert_equal({ key: "custom", max: 100 }, info[:rate_limit])
  end

  # Inheritance

  def test_child_inherits_explain
    parent = build_operation do
      prop :name, String
      guard(:base_check) { false }
      def perform = "ok"
    end
    child = build_operation(parent: parent) do
      guard(:child_check) { true }
    end
    info = child.explain(name: "test")
    assert_equal 2, info[:guards][:results].size
    assert info[:guards][:results][0][:passed]
    refute info[:guards][:results][1][:passed]
    refute info[:callable]
  end

  # Removed pipeline steps

  def test_removed_steps_show_disabled_or_inactive
    # Guard step removed — guards not evaluated
    guard_op = build_operation do
      guard(:blocked) { true }
      pipeline.remove(:guard)
      def perform = "ok"
    end
    info = guard_op.explain
    assert info[:guards][:passed]
    assert_empty info[:guards][:results]
    assert info[:callable]

    # Once step removed
    once_op = build_operation do
      prop :order_id, Integer
      once :order_id
      pipeline.remove(:once)
      def perform = "ok"
    end
    assert_equal({ active: false }, once_op.explain(order_id: 1)[:once])

    # Lock step removed
    lock_op = build_operation do
      advisory_lock "my_lock"
      pipeline.remove(:lock)
      def perform = "ok"
    end
    assert_equal({ active: false }, lock_op.explain[:lock])

    # Transaction step removed
    tx_op = build_operation do
      pipeline.remove(:transaction)
      def perform = "ok"
    end
    refute tx_op.explain[:transaction][:enabled]

    # Callback step removed
    cb_op = build_operation do
      before {}
      pipeline.remove(:callback)
      def perform = "ok"
    end
    assert_equal({ before: 0, after: 0, around: 0 }, cb_op.explain[:callbacks])

    # Rescue step removed
    rescue_op = build_operation do
      rescue_from ArgumentError, as: :bad_input
      pipeline.remove(:rescue)
      def perform = "ok"
    end
    assert_equal({}, rescue_op.explain[:rescue_from])
  end

  def test_removed_record_step_shows_disabled
    op = define_operation(:RemovedRecordExplain) do
      pipeline.remove(:record)
      def perform = "ok"
    end
    with_recording do
      info = op.explain
      assert_equal({ enabled: false }, info[:record])
    end
  end

  # Once misconfigured / invalid statuses

  def test_once_misconfigured_and_invalid_statuses
    # :invalid — nil key
    nil_key_op = define_operation(:OnceExplainNilKey) do
      once { nil }
      def perform = "ok"
    end
    with_recording do
      info = nil_key_op.explain
      assert info[:once][:active]
      assert_nil info[:once][:key]
      assert_equal :invalid, info[:once][:status]
    end

    # :misconfigured — missing once_key column
    no_column_op = define_operation(:OnceExplainNoColumn) do
      prop :order_id, Integer
      once :order_id
      def perform = "ok"
    end
    with_recording(record_class: MinimalOperationRecord) do
      info = no_column_op.explain(order_id: 1)
      assert_equal :misconfigured, info[:once][:status]
    end

    # :misconfigured — anonymous operation
    anon_op = build_operation do
      prop :order_id, Integer
      once :order_id
      def perform = "ok"
    end
    with_recording do
      info = anon_op.explain(order_id: 1)
      assert_equal :misconfigured, info[:once][:status]
    end

    # :misconfigured — record step removed
    removed_op = define_operation(:OnceExplainNoRecord) do
      prop :order_id, Integer
      once :order_id
      pipeline.remove(:record)
      def perform = "ok"
    end
    with_recording do
      info = removed_op.explain(order_id: 1)
      assert_equal :misconfigured, info[:once][:status]
    end

    # :misconfigured — missing expires column
    no_expiry_op = define_operation(:OnceExplainMisconfigured) do
      prop :order_id, Integer
      once :order_id, expires_in: 3600
      def perform = "ok"
    end
    with_recording(record_class: OnceNoExpiryRecord) do
      info = no_expiry_op.explain(order_id: 1)
      assert_equal :misconfigured, info[:once][:status]
    end
  end

  # Callable reflects once status

  def test_callable_reflects_once_status
    # Not callable when pending
    pending_op = define_operation(:CallableOncePending) do
      prop :order_id, Integer
      once :order_id
      def perform = "ok"
    end
    with_recording do
      key = pending_op._once_build_scoped_key(order_id: 99)
      OperationRecord.create!(name: "CallableOncePending", once_key: key, status: "pending")
      info = pending_op.explain(order_id: 99)
      assert_equal :pending, info[:once][:status]
      refute info[:callable]
    end

    # Not callable when unavailable (no backend)
    unavailable_op = define_operation(:CallableOnceNoBackend) do
      prop :order_id, Integer
      once :order_id
      def perform = "ok"
    end
    info = unavailable_op.explain(order_id: 1)
    assert_equal :unavailable, info[:once][:status]
    refute info[:callable]

    # Callable when exists (already ran)
    exists_op = define_operation(:CallableOnceExists) do
      prop :order_id, Integer
      once :order_id
      def perform = "ok"
    end
    with_recording do
      exists_op.call(order_id: 50)
      info = exists_op.explain(order_id: 50)
      assert_equal :exists, info[:once][:status]
      assert info[:callable]
    end
  end

  # Transaction reflects adapter setting

  def test_transaction_explicit_adapter
    op = build_operation do
      transaction :active_record
      def perform = "ok"
    end
    info = op.explain
    assert info[:transaction][:enabled]
  end

  # Partial explain (invalid props)

  def test_partial_missing_required_prop
    op = build_operation do
      prop :name, String
      def perform = "ok"
    end
    info = op.explain
    assert info.key?(:error)
    assert_match(/ArgumentError/, info[:error])
    refute info[:callable]
  end

  def test_partial_wrong_type
    op = build_operation do
      prop :count, Integer
      def perform = "ok"
    end
    info = op.explain(count: "not a number")
    assert info.key?(:error)
    assert_match(/Literal::TypeError/, info[:error])
  end

  def test_partial_no_error_key_on_success
    op = build_operation { def perform = "ok" }
    info = op.explain
    refute info.key?(:error)
  end

  def test_partial_still_frozen
    op = build_operation do
      prop :name, String
      def perform = "ok"
    end
    info = op.explain(name: 123)
    assert info.frozen?
  end

  def test_partial_props_empty
    op = build_operation do
      prop :name, String
      prop :count, Integer
      def perform = "ok"
    end
    info = op.explain(name: 123)
    assert_equal({}, info[:props])
  end

  def test_partial_class_level_info_still_available
    op = define_operation(:PartialClassLevel) do
      prop :name, String
      before {}
      after {}
      rescue_from ArgumentError, as: :bad_input
      def perform = "ok"
    end
    with_recording do
      info = op.explain(name: 123)
      assert info[:record][:enabled]
      assert info[:transaction][:enabled]
      assert_equal({ "ArgumentError" => :bad_input }, info[:rescue_from])
      assert_equal({ before: 1, after: 1, around: 0 }, info[:callbacks])
      assert_equal %i[trace result guard once lock record transaction rescue callback], info[:pipeline]
    end
  end

  def test_partial_guards_not_evaluated
    op = build_operation do
      prop :name, String
      guard(:check, "Name required") { name.nil? }
      def perform = "ok"
    end
    info = op.explain(name: 123)
    refute info[:guards][:passed]
    assert_empty info[:guards][:results]
  end

  def test_partial_once_shows_active_with_invalid_key
    op = define_operation(:PartialOnce) do
      prop :order_id, Integer
      once :order_id
      def perform = "ok"
    end
    with_recording do
      info = op.explain(order_id: "bad")
      assert info[:once][:active]
      assert_nil info[:once][:key]
      assert_equal :invalid, info[:once][:status]
    end
  end

  def test_partial_lock_key_resolution
    # Dynamic lock — nil key (can't evaluate with bad props)
    dynamic_op = build_operation do
      prop :order_id, Integer
      advisory_lock { "order:#{order_id}" }
      def perform = "ok"
    end
    info = dynamic_op.explain(order_id: "bad")
    assert info[:lock][:active]
    assert_nil info[:lock][:key]

    # Static string key — preserved despite bad props
    static_op = build_operation do
      prop :name, String
      advisory_lock "global_lock"
      def perform = "ok"
    end
    info = static_op.explain(name: 123)
    assert info[:lock][:active]
    assert_equal "global_lock", info[:lock][:key]

    # No-arg lock — class name as key, preserved despite bad props
    define_operation(:PartialLockNamed) do
      prop :name, String
      advisory_lock
      def perform = "ok"
    end
    info = PartialLockNamed.explain(name: 123)
    assert info[:lock][:active]
    assert_equal "PartialLockNamed", info[:lock][:key]
  end

  def test_partial_context_sources
    # Ambient source — mappings and source preserved, resolved empty (invalid props)
    ambient_op = build_operation do
      prop :user, String
      prop :count, Integer
      context user: :current_user
      def perform = "ok"
    end
    Dex.with_context(current_user: "admin") do
      info = ambient_op.explain(count: "bad")
      assert info.key?(:error)
      assert_equal({ user: :current_user }, info[:context][:mappings])
      assert_equal({ user: :ambient }, info[:context][:source])
      assert_equal({}, info[:context][:resolved])
    end

    # Explicit source detected
    explicit_op = build_operation do
      prop :user, String
      prop :role, String
      context user: :current_user
      def perform = "ok"
    end
    info = explicit_op.explain(user: "explicit_user")
    assert_equal :explicit, info[:context][:source][:user]
    assert_equal({}, info[:context][:resolved])

    # Missing source (no ambient, no default)
    missing_op = build_operation do
      prop :user, String
      context user: :current_user
      def perform = "ok"
    end
    info = missing_op.explain
    assert info.key?(:error)
    assert_equal :missing, info[:context][:source][:user]

    # Default source
    default_op = build_operation do
      prop :locale, String, default: "en"
      prop :count, Integer
      context :locale
      def perform = "ok"
    end
    info = default_op.explain(count: "bad")
    assert info.key?(:error)
    assert_equal :default, info[:context][:source][:locale]
  end

  def test_partial_custom_middleware_not_called
    hook_called = false
    class_methods = Module.new do
      define_method(:_rate_limit_explain) do |_instance, info|
        hook_called = true
        info[:rate_limit] = { max: 100 }
      end
    end
    wrapper = Module.new do
      define_singleton_method(:name) { "RateLimitWrapper" }
      define_method(:included) do |base|
        base.extend(class_methods)
        super(base)
      end
      module_function :included
      define_method(:_rate_limit_wrap) { yield }
    end
    op = build_operation do
      use wrapper
      prop :name, String
      def perform = "ok"
    end
    info = op.explain(name: 123)
    refute hook_called
    refute info.key?(:rate_limit)
  end

  def test_partial_operation_name_still_reported
    define_operation(:PartialNamed) do
      prop :name, String
      def perform = "ok"
    end
    info = PartialNamed.explain(name: 123)
    assert_equal "PartialNamed", info[:operation]
  end

  def test_non_validation_errors_still_raise
    op = build_operation do
      prop :name, String
      def perform = "ok"
    end
    op.define_singleton_method(:new) do |**kwargs|
      super(**kwargs)
      raise NoMethodError, "bug in init hook"
    end
    assert_raises(NoMethodError) { op.explain(name: "valid") }
  end
end
