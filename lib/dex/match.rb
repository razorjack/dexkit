# frozen_string_literal: true

module Dex
  # Top-level aliases for clean pattern matching
  Ok = Operation::Ok
  Err = Operation::Err

  # Module for including Ok/Err constants without namespace prefix
  module Match
    Ok = Dex::Ok
    Err = Dex::Err
  end
end
