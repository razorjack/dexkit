# frozen_string_literal: true

require "securerandom"

module Dex
  module Id
    ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    TIMESTAMP_WIDTH = 8
    RANDOM_WIDTH = 12

    module_function

    def generate(prefix)
      "#{prefix}#{base58_encode(current_milliseconds, TIMESTAMP_WIDTH)}#{random_suffix(RANDOM_WIDTH)}"
    end

    def base58_encode(number, width = nil)
      encoded = +""
      value = number.to_i

      loop do
        value, remainder = value.divmod(ALPHABET.length)
        encoded.prepend(ALPHABET[remainder])
        break unless value.positive?
      end

      width ? encoded.rjust(width, ALPHABET[0]) : encoded
    end

    def random_suffix(width)
      Array.new(width) { ALPHABET[SecureRandom.random_number(ALPHABET.length)] }.join
    end

    def current_milliseconds
      Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
    end
  end
end
