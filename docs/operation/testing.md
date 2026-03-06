---
description: Test Dex::Operation with dexkit's Minitest helpers – execution, assertions, contract checks, stubs, spies, and rollback behavior.
---

# Testing

dexkit ships test helpers for Minitest with execution helpers, assertions, stubbing, spying, and a global activity log. Everything is designed to keep tests short and readable.

## Setup

```ruby
# test/test_helper.rb
require "dex/test_helpers"

class Minitest::Test
  include Dex::TestHelpers
end
```

Including `Dex::TestHelpers` automatically installs the test wrapper (which records all operation calls to `TestLog`) and clears state between tests.

## Subject declaration

Set a default operation class for all helpers in a test class:

```ruby
class OnboardEmployeeTest < Minitest::Test
  testing Employee::Onboard

  def test_onboards_employee
    result = call_operation(name: "Alice", email: "alice@example.com")
    assert_ok result
  end
end
```

With `testing`, you don't need to pass the class to every helper call. You can still pass an explicit class when needed.

## Calling operations

Two helpers that mirror the two calling conventions:

```ruby
# Safe call – returns Ok or Err, never raises
result = call_operation(name: "Alice")

# Direct call – returns value or raises Dex::Error
value = call_operation!(name: "Alice")

# Explicit class (overrides `testing` subject)
result = call_operation(Employee::Onboard, name: "Alice")
```

## Result assertions

```ruby
# Assert success
assert_ok result                     # passes if Ok
assert_ok result, expected_value     # also checks the value
assert_ok(result) { |value|          # block form for complex checks
  assert_equal "Alice", value.name
}

# Assert failure
assert_err result, :not_found                         # checks error code
assert_err result, :fail, message: "went wrong"       # checks message (exact)
assert_err result, :fail, message: /went wrong/       # checks message (regex)
assert_err result, :fail, details: { field: "email" } # checks details
assert_err(result, :fail) { |error|                   # block form
  assert_includes error.message, "wrong"
}

# Refutations
refute_ok result                     # passes if Err
refute_err result, :not_found        # passes if Ok or different code
```

## One-liner assertions

Call the operation and assert the result in a single line:

```ruby
# Assert success, optionally check return value
assert_operation(name: "Alice", returns: employee)

# Assert failure with error code
assert_operation_error(:invalid, name: "")

# With explicit class
assert_operation(Employee::Onboard, name: "Alice")
assert_operation_error(Employee::Onboard, :invalid, name: "")

# With message/details checks
assert_operation_error(:invalid, message: /required/, name: "")
```

## Contract assertions

Inspect declarations without calling the operation:

```ruby
# Exhaustive param names – fails if extra or missing
assert_params(:name, :email)

# Subset check – just verifies these exist
assert_accepts_param(:name)

# Params with types
assert_params(name: String, email: String)

# Success type
assert_success_type(_Ref(Employee))

# Exhaustive error codes
assert_error_codes(:not_found, :invalid)

# Full contract in one call
assert_contract(
  params: [:name, :email],
  success: _Ref(Employee),
  errors: [:not_found, :invalid]
)

# Params as a type hash in assert_contract
assert_contract(params: { name: String, email: String })
```

## Param validation

```ruby
# Assert that invalid params raise Literal::TypeError
assert_invalid_params(name: 123)

# Assert that valid params don't raise
assert_valid_params(name: "Alice", email: "a@b.com")
```

## Stubbing

Replace an operation entirely within a block:

```ruby
stub_operation(Order::SendConfirmation, returns: true) do
  result = call_operation!(name: "Alice")
  # Order::SendConfirmation.call inside Employee::Onboard returns true without executing perform
end

stub_operation(Order::Charge, error: :timeout) do
  result = call_operation(amount: 100)
  assert_err result, :timeout
end

# Error stub with full details
stub_operation(Order::SendConfirmation, error: { code: :failed, message: "SMTP down" }) do
  result = call_operation(name: "Alice")
  assert_err result, :failed, message: "SMTP down"
end
```

Stubs are scoped to the block and automatically cleared afterward.

## Spying

Observe real execution without modifying behavior:

```ruby
spy_on_operation(Order::SendConfirmation) do |spy|
  call_operation!(name: "Alice")

  assert spy.called?
  assert spy.called_once?
  assert_equal 1, spy.call_count
  assert spy.called_with?(email: "alice@example.com")

  spy.last_result  # => Ok or Err
end
```

## Transaction assertions

```ruby
# Assert that the operation rolls back (expects Dex::Error to be raised)
assert_rolls_back(Employee) { Employee::Onboard.new(bad: true).call }

# Assert that the operation commits
assert_commits(Employee) { Employee::Onboard.new(name: "Alice").call }
```

## Async assertions

Requires `ActiveJob::TestHelper` to be included in your test class:

```ruby
class SendConfirmationTest < Minitest::Test
  include ActiveJob::TestHelper

  testing Order::SendConfirmation

  def test_enqueues_job
    assert_enqueues_operation(order_id: 123)
    assert_enqueues_operation(order_id: 123, queue: "mailers")
  end

  def test_does_not_enqueue
    refute_enqueues_operation { some_action }
  end
end
```

## Batch assertions

Test multiple inputs at once:

```ruby
assert_all_succeed(params_list: [
  { amount: 10 },
  { amount: 20 },
  { amount: 30 }
])

assert_all_fail(code: :invalid, params_list: [
  { amount: -1 },
  { amount: 0 }
])
```

Both report which specific cases failed, with their index and params.

## TestLog

All operation calls are recorded to `Dex::TestLog` during tests. The log is cleared automatically between tests.

```ruby
Dex::TestLog.calls                     # => [Entry, ...]
Dex::TestLog.size                      # => Integer
Dex::TestLog.empty?                    # => true/false
Dex::TestLog.find(Employee::Onboard)          # => entries for Employee::Onboard
Dex::TestLog.find(Employee::Onboard, name: "Alice")  # filter by params
Dex::TestLog.summary                   # human-readable summary
```

Each entry is a `Data.define` with:

| Field | Type | Description |
|---|---|---|
| `type` | String | Always `"Operation"` |
| `name` | String | Operation class name |
| `operation_class` | Class | The operation class |
| `params` | Hash | Properties passed to the operation |
| `result` | Ok or Err | The outcome |
| `duration` | Float | Execution time in seconds |
| `caller_location` | Thread::Backtrace::Location | Where the call originated |
