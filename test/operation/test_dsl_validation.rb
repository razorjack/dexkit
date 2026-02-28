# frozen_string_literal: true

require "test_helper"

class TestDSLValidation < Minitest::Test
  # --- error(*codes) ---

  def test_error_rejects_strings
    assert_raises(ArgumentError, /must be Symbols/) do
      build_operation { error "not_found" }
    end
  end

  def test_error_rejects_integers
    assert_raises(ArgumentError, /must be Symbols/) do
      build_operation { error 42 }
    end
  end

  def test_error_accepts_symbols
    op = build_operation { error :not_found, :invalid }
    assert_equal [:not_found, :invalid], op._declared_errors
  end

  # --- rescue_from ---

  def test_rescue_from_rejects_non_exception_class
    assert_raises(ArgumentError, /expects Exception subclasses/) do
      build_operation { rescue_from String, as: :bad }
    end
  end

  def test_rescue_from_rejects_non_symbol_as
    assert_raises(ArgumentError, /must be a Symbol/) do
      build_operation { rescue_from StandardError, as: "not_a_symbol" }
    end
  end

  def test_rescue_from_rejects_empty_classes
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

  def test_record_rejects_unknown_options
    assert_raises(ArgumentError, /unknown record option/) do
      build_operation { record ttl: 30 }
    end
  end

  def test_record_rejects_invalid_first_arg
    assert_raises(ArgumentError, /record expects true, false, or nil/) do
      build_operation { record :foo }
    end
  end

  def test_record_accepts_known_options
    op = build_operation { record params: false }
    assert_equal false, op.settings_for(:record)[:params]
  end

  # --- advisory_lock ---

  def test_advisory_lock_rejects_bad_key_type
    assert_raises(ArgumentError, /must be a String, Symbol, or Proc/) do
      build_operation { advisory_lock 123 }
    end
  end

  def test_advisory_lock_rejects_non_numeric_timeout
    assert_raises(ArgumentError, /must be Numeric/) do
      build_operation { advisory_lock "key", timeout: "five" }
    end
  end

  def test_advisory_lock_accepts_string_key
    op = build_operation { advisory_lock "my-lock" }
    assert_equal "my-lock", op.settings_for(:advisory_lock)[:key]
  end

  def test_advisory_lock_accepts_symbol_key
    op = build_operation { advisory_lock :compute_key }
    assert_equal :compute_key, op.settings_for(:advisory_lock)[:key]
  end

  def test_advisory_lock_accepts_block
    op = build_operation { advisory_lock { "dynamic" } }
    assert op.settings_for(:advisory_lock)[:key].is_a?(Proc)
  end

  def test_advisory_lock_accepts_numeric_timeout
    op = build_operation { advisory_lock "key", timeout: 5 }
    assert_equal 5, op.settings_for(:advisory_lock)[:timeout]
  end

  def test_advisory_lock_rejects_unknown_options
    assert_raises(ArgumentError, /unknown advisory_lock option/) do
      build_operation { advisory_lock "key", retries: 3 }
    end
  end

  # --- before / after / around ---

  def test_before_rejects_string
    assert_raises(ArgumentError, /must be a Symbol or callable/) do
      build_operation { before "not_valid" }
    end
  end

  def test_after_rejects_integer
    assert_raises(ArgumentError, /must be a Symbol or callable/) do
      build_operation { after 42 }
    end
  end

  def test_around_rejects_nil_without_block
    assert_raises(ArgumentError, /requires a Symbol, callable, or block/) do
      build_operation { around }
    end
  end

  def test_before_accepts_symbol
    op = build_operation { before :setup }
    assert_equal [[:method, :setup]], op._callback_list(:before)
  end

  def test_after_accepts_lambda
    callable = -> {}
    op = build_operation { after callable }
    assert_equal [[:proc, callable]], op._callback_list(:after)
  end

  def test_around_accepts_block
    op = build_operation { around { |c| c.call } }
    assert_equal 1, op._callback_list(:around).size
  end

  # --- transaction ---

  def test_transaction_rejects_unknown_adapter_symbol
    assert_raises(ArgumentError, /unknown transaction adapter/) do
      build_operation { transaction :redis }
    end
  end

  def test_transaction_rejects_unknown_adapter_option
    assert_raises(ArgumentError, /unknown transaction adapter/) do
      build_operation { transaction adapter: :redis }
    end
  end

  def test_transaction_rejects_bad_first_arg
    assert_raises(ArgumentError, /expects true, false, nil, or a Symbol/) do
      build_operation { transaction 42 }
    end
  end

  def test_transaction_accepts_false
    op = build_operation { transaction false }
    assert_equal false, op.settings_for(:transaction)[:enabled]
  end

  def test_transaction_rejects_unknown_options
    assert_raises(ArgumentError, /unknown transaction option/) do
      build_operation { transaction true, retries: 2 }
    end
  end

  def test_transaction_accepts_valid_adapter
    op = build_operation { transaction :mongoid }
    assert_equal :mongoid, op.settings_for(:transaction)[:adapter]
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
