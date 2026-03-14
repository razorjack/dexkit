# frozen_string_literal: true

require "test_helper"

class TestDSLValidation < Minitest::Test
  # --- error(*codes) ---

  def test_error_rejects_non_symbols
    assert_raises(ArgumentError, /must be Symbols/) do
      build_operation { error "not_found" }
    end

    assert_raises(ArgumentError, /must be Symbols/) do
      build_operation { error 42 }
    end
  end

  def test_error_accepts_symbols
    op = build_operation { error :not_found, :invalid }
    assert_equal [:not_found, :invalid], op._declared_errors
  end

  # --- rescue_from ---

  def test_rescue_from_rejects_invalid_args
    assert_raises(ArgumentError, /expects Exception subclasses/) do
      build_operation { rescue_from String, as: :bad }
    end

    assert_raises(ArgumentError, /must be a Symbol/) do
      build_operation { rescue_from StandardError, as: "not_a_symbol" }
    end

    assert_raises(ArgumentError, /requires at least one exception class/) do
      build_operation { rescue_from as: :oops }
    end
  end

  def test_rescue_from_accepts_valid_args
    op = build_operation { rescue_from StandardError, RuntimeError, as: :fail }
    assert_equal 2, op._rescue_handlers.size
  end

  # --- async (class-level) ---

  def test_async_rejects_unknown_options
    assert_raises(ArgumentError, /unknown async option/) do
      build_operation { async queue: "low", priority: 5 }
    end
  end

  def test_async_accepts_known_options
    op = build_operation { async queue: "low" }
    assert_equal({ queue: "low" }, op.settings_for(:async))
  end

  # --- record ---

  def test_record_rejects_invalid_input
    assert_raises(ArgumentError, /unknown record option/) do
      build_operation { record ttl: 30 }
    end

    assert_raises(ArgumentError, /record expects true, false, or nil/) do
      build_operation { record :foo }
    end
  end

  def test_record_accepts_known_options
    op = build_operation { record params: false }
    assert_equal false, op.settings_for(:record)[:params]
  end

  # --- advisory_lock ---

  def test_advisory_lock_rejects_invalid_input
    assert_raises(ArgumentError, /must be a String, Symbol, or Proc/) do
      build_operation { advisory_lock 123 }
    end

    assert_raises(ArgumentError, /must be Numeric/) do
      build_operation { advisory_lock "key", timeout: "five" }
    end

    assert_raises(ArgumentError, /unknown advisory_lock option/) do
      build_operation { advisory_lock "key", retries: 3 }
    end
  end

  def test_advisory_lock_accepts_valid_input
    op1 = build_operation { advisory_lock "my-lock" }
    assert_equal "my-lock", op1.settings_for(:advisory_lock)[:key]

    op2 = build_operation { advisory_lock :compute_key }
    assert_equal :compute_key, op2.settings_for(:advisory_lock)[:key]

    op3 = build_operation { advisory_lock { "dynamic" } }
    assert op3.settings_for(:advisory_lock)[:key].is_a?(Proc)

    op4 = build_operation { advisory_lock "key", timeout: 5 }
    assert_equal 5, op4.settings_for(:advisory_lock)[:timeout]
  end

  # --- before / after / around ---

  def test_callback_rejects_invalid_forms
    assert_raises(ArgumentError, /must be a Symbol or Proc/) do
      build_operation { before "not_valid" }
    end

    assert_raises(ArgumentError, /must be a Symbol or Proc/) do
      build_operation { after 42 }
    end

    assert_raises(ArgumentError, /requires a Symbol, Proc, or block/) do
      build_operation { around }
    end
  end

  def test_callback_accepts_valid_forms
    op1 = build_operation { before :setup }
    assert_equal [[:method, :setup]], op1._callback_list(:before)

    callable = -> {}
    op2 = build_operation { after callable }
    assert_equal [[:proc, callable]], op2._callback_list(:after)

    op3 = build_operation { around { |c| c.call } }
    assert_equal 1, op3._callback_list(:around).size
  end

  # --- transaction ---

  def test_transaction_rejects_invalid_input
    assert_raises(ArgumentError, /unknown transaction adapter/) do
      build_operation { transaction :redis }
    end

    assert_raises(ArgumentError, /unknown transaction adapter/) do
      build_operation { transaction adapter: :redis }
    end

    assert_raises(ArgumentError, /expects true, false, nil, or a Symbol/) do
      build_operation { transaction 42 }
    end

    assert_raises(ArgumentError, /unknown transaction option/) do
      build_operation { transaction true, retries: 2 }
    end
  end

  def test_transaction_accepts_valid_input
    op1 = build_operation { transaction false }
    assert_equal false, op1.settings_for(:transaction)[:enabled]

    op2 = build_operation { transaction :active_record }
    assert_equal :active_record, op2.settings_for(:transaction)[:adapter]
  end

  # --- async (runtime) ---

  def test_runtime_async_rejects_unknown_options
    op = build_operation { def perform = "ok" }
    assert_raises(ArgumentError, /unknown async option/) do
      op.new.async(priority: 5)
    end
  end

  def test_runtime_async_accepts_known_options
    op = build_operation { def perform = "ok" }
    proxy = op.new.async(queue: "low")
    assert_instance_of Dex::Operation::AsyncProxy, proxy
  end
end
