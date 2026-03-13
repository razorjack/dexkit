# frozen_string_literal: true

require "test_helper"

class TestId < Minitest::Test
  # --- generate ---

  def test_generate_returns_prefixed_id
    id = Dex::Id.generate("ord_")
    assert id.start_with?("ord_")
  end

  def test_generate_payload_length_with_defaults
    id = Dex::Id.generate("ord_")
    payload = id.delete_prefix("ord_")
    assert_equal 20, payload.length # 8 timestamp + 12 random
  end

  def test_generate_with_internal_underscore_prefix
    id = Dex::Id.generate("order_item_")
    assert id.start_with?("order_item_")
  end

  def test_generate_with_numeric_prefix
    id = Dex::Id.generate("v2_order_")
    assert id.start_with?("v2_order_")
  end

  def test_generate_ids_are_unique
    ids = Array.new(100) { Dex::Id.generate("ord_") }
    assert_equal 100, ids.uniq.size
  end

  def test_generate_ids_use_base58_alphabet
    id = Dex::Id.generate("x_")
    payload = id.delete_prefix("x_")
    payload.each_char do |char|
      assert_includes Dex::Id::ALPHABET, char
    end
  end

  # --- generate: random: kwarg ---

  def test_generate_custom_random_width
    id = Dex::Id.generate("ord_", random: 16)
    payload = id.delete_prefix("ord_")
    assert_equal 24, payload.length # 8 timestamp + 16 random
  end

  def test_generate_minimum_random_width
    id = Dex::Id.generate("ord_", random: 8)
    payload = id.delete_prefix("ord_")
    assert_equal 16, payload.length # 8 timestamp + 8 random
  end

  def test_generate_rejects_random_below_minimum
    error = assert_raises(ArgumentError) { Dex::Id.generate("ord_", random: 7) }
    assert_match(/random: must be an Integer >= 8/, error.message)
  end

  def test_generate_rejects_zero_random
    assert_raises(ArgumentError) { Dex::Id.generate("ord_", random: 0) }
  end

  def test_generate_rejects_negative_random
    assert_raises(ArgumentError) { Dex::Id.generate("ord_", random: -1) }
  end

  def test_generate_rejects_non_integer_random
    error = assert_raises(ArgumentError) { Dex::Id.generate("ord_", random: 12.5) }
    assert_match(/random: must be an Integer/, error.message)
  end

  def test_generate_rejects_string_random
    assert_raises(ArgumentError) { Dex::Id.generate("ord_", random: "12") }
  end

  # --- generate: prefix validation ---

  def test_generate_rejects_uppercase_prefix
    error = assert_raises(ArgumentError) { Dex::Id.generate("Op_") }
    assert_match(/must match/, error.message)
  end

  def test_generate_rejects_prefix_without_trailing_underscore
    error = assert_raises(ArgumentError) { Dex::Id.generate("ord") }
    assert_match(/must end with underscore/, error.message)
    assert_match(/Did you mean "ord_"/, error.message)
  end

  def test_generate_rejects_empty_prefix
    error = assert_raises(ArgumentError) { Dex::Id.generate("") }
    assert_match(/non-empty String/, error.message)
  end

  def test_generate_rejects_nil_prefix
    error = assert_raises(ArgumentError) { Dex::Id.generate(nil) }
    assert_match(/non-empty String/, error.message)
  end

  def test_generate_rejects_integer_prefix
    error = assert_raises(ArgumentError) { Dex::Id.generate(123) }
    assert_match(/non-empty String/, error.message)
  end

  def test_generate_rejects_array_prefix
    error = assert_raises(ArgumentError) { Dex::Id.generate([]) }
    assert_match(/non-empty String/, error.message)
  end

  def test_generate_rejects_prefix_starting_with_number
    error = assert_raises(ArgumentError) { Dex::Id.generate("2order_") }
    assert_match(/must match/, error.message)
  end

  def test_generate_rejects_prefix_starting_with_underscore
    error = assert_raises(ArgumentError) { Dex::Id.generate("_ord_") }
    assert_match(/must match/, error.message)
  end

  def test_generate_accepts_internal_prefixes
    %w[op_ ev_ tr_ hd_].each do |prefix|
      id = Dex::Id.generate(prefix)
      assert id.start_with?(prefix), "Expected #{id} to start with #{prefix}"
    end
  end

  # --- parse ---

  def test_parse_round_trips_with_generate
    id = Dex::Id.generate("ord_")
    parsed = Dex::Id.parse(id)

    assert_equal "ord_", parsed.prefix
    assert_instance_of Time, parsed.created_at
    assert parsed.created_at.utc?
    assert_equal 12, parsed.random.length
  end

  def test_parse_extracts_timestamp_within_tolerance
    before = Time.now.utc
    id = Dex::Id.generate("ord_")
    after = Time.now.utc

    parsed = Dex::Id.parse(id)
    assert_operator parsed.created_at, :>=, before.floor(3)
    assert_operator parsed.created_at, :<=, after.ceil(3)
  end

  def test_parse_with_internal_underscore_prefix
    id = Dex::Id.generate("order_item_")
    parsed = Dex::Id.parse(id)

    assert_equal "order_item_", parsed.prefix
  end

  def test_parse_with_custom_random_width
    id = Dex::Id.generate("ord_", random: 16)
    parsed = Dex::Id.parse(id)

    assert_equal "ord_", parsed.prefix
    assert_equal 16, parsed.random.length
  end

  def test_parse_returns_data_object
    parsed = Dex::Id.parse(Dex::Id.generate("ord_"))
    assert_kind_of Data, parsed
    assert_instance_of Dex::Id::Parsed, parsed
  end

  def test_parse_result_is_frozen
    parsed = Dex::Id.parse(Dex::Id.generate("ord_"))
    assert parsed.frozen?
  end

  def test_parse_rejects_string_without_underscore
    error = assert_raises(ArgumentError) { Dex::Id.parse("abc123") }
    assert_match(/no underscore found/, error.message)
  end

  def test_parse_rejects_short_payload
    error = assert_raises(ArgumentError) { Dex::Id.parse("ord_12345678") }
    assert_match(/need at least 9/, error.message)
  end

  def test_parse_rejects_invalid_base58_characters
    id = Dex::Id.generate("ord_")
    bad_id = id[0..-2] + "0" # '0' is not in base58
    error = assert_raises(ArgumentError) { Dex::Id.parse(bad_id) }
    assert_match(/invalid base58 character/, error.message)
  end

  def test_parse_rejects_ambiguous_characters
    bad_id = "ord_12345678IIIIIIIIIIII" # 'I' is not in base58
    error = assert_raises(ArgumentError) { Dex::Id.parse(bad_id) }
    assert_match(/invalid base58 character "I"/, error.message)
  end

  # --- base58 encode/decode round-trip ---

  def test_base58_round_trip
    ms = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
    encoded = Dex::Id.base58_encode(ms, 8)
    decoded = Dex::Id.base58_decode(encoded)
    assert_equal ms, decoded
  end

  def test_base58_encode_zero
    assert_equal "1", Dex::Id.base58_encode(0)
    assert_equal "11111111", Dex::Id.base58_encode(0, 8)
  end

  def test_base58_decode_single_char
    assert_equal 0, Dex::Id.base58_decode("1")
    assert_equal 1, Dex::Id.base58_decode("2")
    assert_equal 57, Dex::Id.base58_decode("z")
  end

  def test_base58_decode_rejects_invalid_characters
    error = assert_raises(ArgumentError) { Dex::Id.base58_decode("abc0def") }
    assert_match(/invalid base58 character "0"/, error.message)
  end

  def test_base58_decode_rejects_nil
    error = assert_raises(ArgumentError) { Dex::Id.base58_decode(nil) }
    assert_match(/expected a String/, error.message)
  end

  def test_base58_decode_rejects_integer
    error = assert_raises(ArgumentError) { Dex::Id.base58_decode(123) }
    assert_match(/expected a String/, error.message)
  end

  # --- sortability ---

  def test_ids_with_same_prefix_sort_chronologically
    ids = Array.new(10) do
      id = Dex::Id.generate("ord_")
      sleep 0.002
      id
    end
    assert_equal ids, ids.sort
  end
end
