# frozen_string_literal: true

require "securerandom"

module Dex
  module Id
    ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    BASE = ALPHABET.length
    TIMESTAMP_WIDTH = 8
    DEFAULT_RANDOM_WIDTH = 12
    MIN_RANDOM_WIDTH = 8
    PREFIX_PATTERN = /\A[a-z][a-z0-9_]*_\z/
    MIN_PAYLOAD_LENGTH = 9 # 8 timestamp + at least 1 random

    ALPHABET_INDEX = ALPHABET.each_char.with_index.to_h.freeze

    Parsed = Data.define(:prefix, :created_at, :random)

    module_function

    def generate(prefix, random: DEFAULT_RANDOM_WIDTH)
      validate_prefix!(prefix)
      validate_random_width!(random)

      "#{prefix}#{base58_encode(current_milliseconds, TIMESTAMP_WIDTH)}#{random_suffix(random)}"
    end

    def parse(id)
      id = String(id)
      last_underscore = id.rindex("_")

      unless last_underscore
        raise ArgumentError,
          "Cannot parse #{id.inspect}: no underscore found. Dex::Id strings have the format \"prefix_<timestamp><random>\"."
      end

      prefix = id[0..last_underscore]
      payload = id[(last_underscore + 1)..]

      if payload.length < MIN_PAYLOAD_LENGTH
        raise ArgumentError,
          "Cannot parse #{id.inspect}: payload after prefix is #{payload.length} characters, " \
          "need at least #{MIN_PAYLOAD_LENGTH} (#{TIMESTAMP_WIDTH} timestamp + 1 random)."
      end

      validate_base58!(payload, id)

      timestamp_chars = payload[0, TIMESTAMP_WIDTH]
      random_chars = payload[TIMESTAMP_WIDTH..]

      ms = base58_decode(timestamp_chars)
      created_at = Time.at(ms / 1000, ms % 1000 * 1000, :usec).utc

      Parsed.new(prefix: prefix, created_at: created_at, random: random_chars)
    end

    def base58_encode(number, width = nil)
      encoded = +""
      value = number.to_i

      loop do
        value, remainder = value.divmod(BASE)
        encoded.prepend(ALPHABET[remainder])
        break unless value.positive?
      end

      width ? encoded.rjust(width, ALPHABET[0]) : encoded
    end

    def base58_decode(string)
      raise ArgumentError, "expected a String, got #{string.inspect}" unless string.is_a?(String)

      value = 0
      string.each_char do |char|
        index = ALPHABET_INDEX[char]
        raise ArgumentError, "invalid base58 character #{char.inspect} in #{string.inspect}" unless index

        value = value * BASE + index
      end
      value
    end

    def random_suffix(width)
      Array.new(width) { ALPHABET[SecureRandom.random_number(BASE)] }.join
    end

    def current_milliseconds
      Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
    end

    def validate_prefix!(prefix)
      raise ArgumentError, "prefix must be a non-empty String" unless prefix.is_a?(String) && !prefix.empty?

      return if PREFIX_PATTERN.match?(prefix)

      unless prefix.end_with?("_")
        raise ArgumentError,
          "Invalid prefix #{prefix.inspect}: prefix must end with underscore. Did you mean #{"#{prefix}_".inspect}?"
      end

      raise ArgumentError,
        "Invalid prefix #{prefix.inspect}: prefix must match #{PREFIX_PATTERN.inspect} " \
        "(lowercase alphanumeric with internal underscores, ending in underscore)."
    end
    private_class_method :validate_prefix!

    def validate_random_width!(width)
      unless width.is_a?(Integer) && width >= MIN_RANDOM_WIDTH
        raise ArgumentError,
          "random: must be an Integer >= #{MIN_RANDOM_WIDTH}, got #{width.inspect}."
      end
    end
    private_class_method :validate_random_width!

    def validate_base58!(payload, original_id)
      payload.each_char do |char|
        next if ALPHABET_INDEX.key?(char)

        raise ArgumentError,
          "Cannot parse #{original_id.inspect}: invalid base58 character #{char.inspect} in payload."
      end
    end
    private_class_method :validate_base58!
  end
end
