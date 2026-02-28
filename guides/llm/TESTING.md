# Dex::TestHelpers — Complete Reference

Test helpers for `Dex::Operation`. Provides assertions, stubbing, spying, and a global activity log.

## Setup

```ruby
# test/test_helper.rb
require "dex/test_helpers"

class Minitest::Test
  include Dex::TestHelpers
end
```

`Dex::TestHelpers` is **not** autoloaded — it stays out of production runtime entirely.

## Architecture

```
Dex::TestHelpers (include in test classes)
  ├── testing(klass)                    # set subject
  ├── call_operation / call_operation!  # execute operations
  ├── assert_ok / assert_err           # result assertions
  ├── assert_operation / _error        # one-liner call+assert
  ├── assert_params / _contract / ...  # contract assertions
  ├── stub_operation                   # replace operation
  └── spy_on_operation                 # observe operation
                │
         Dex::TestLog     (global activity log)
                │
         Dex::TestWrapper (prepended on Dex::Operation once)
```

**TestWrapper** prepends `call` on `Dex::Operation` base class. Since pipeline steps wrap `perform` via `call`, this intercepts at the outermost layer. Stubs bypass the entire pipeline; real calls are recorded to TestLog.

**TestLog** is automatically cleared in `setup`. Stubs are also cleared.

---

## Subject Declaration

```ruby
class MyOperationTest < Minitest::Test
  include Dex::TestHelpers

  testing MyOperation  # sets default operation for all helpers

  def test_it_works
    result = call_operation(name: "Alice")  # uses MyOperation
    assert_ok result
  end
end
```

All helpers accept an explicit class as first arg, falling back to the subject.

---

## Execution Helpers

| Method | Returns | Behavior |
|--------|---------|----------|
| `call_operation(**params)` | `Ok` or `Err` | Uses subject, wraps in `.safe.call` |
| `call_operation(MyOp, **params)` | `Ok` or `Err` | Explicit class |
| `call_operation!(**params)` | raw value | Uses subject, direct `.call` (may raise) |
| `call_operation!(MyOp, **params)` | raw value | Explicit class, direct call |

```ruby
result = call_operation(name: "Alice")     # => Ok or Err
value  = call_operation!(name: "Alice")    # => "Alice" or raises Dex::Error
```

---

## Result Assertions

Work with `Ok`/`Err` objects from `call_operation`.

### assert_ok

```ruby
assert_ok result                        # passes if Ok
assert_ok result, 42                    # passes if Ok with value == 42
assert_ok(result) { |val| ... }         # yields value for custom checks
```

### refute_ok

```ruby
refute_ok result                        # passes if Err
```

### assert_err

```ruby
assert_err result                       # passes if Err
assert_err result, :not_found           # checks error code
assert_err result, :fail, message: "x"  # checks code + message (String)
assert_err result, :fail, message: /x/  # checks code + message (Regex)
assert_err result, :fail, details: { field: "email" }  # checks details
assert_err(result, :fail) { |err| ... } # yields Dex::Error for custom checks
```

### refute_err

```ruby
refute_err result                       # passes if Ok
refute_err result, :not_found           # passes if Ok OR different error code
```

---

## One-Liner Assertions

Call + assert in one shot. Use subject or pass explicit class.

### assert_operation

```ruby
assert_operation(name: "Alice")                     # subject, asserts Ok
assert_operation(MyOp, name: "Alice")               # explicit class
assert_operation(MyOp, name: "Alice", returns: 42)  # also checks return value
```

### assert_operation_error

```ruby
assert_operation_error(:not_found, id: 999)                  # subject + code
assert_operation_error(MyOp, :not_found, id: 999)            # explicit class
assert_operation_error(MyOp, :fail, x: 1, message: "oops")   # checks message
assert_operation_error(MyOp, :fail, x: 1, message: /oops/)   # regex message
```

---

## Contract Assertions

Inspect class declarations without calling the operation.

### assert_params

```ruby
# Exhaustive name check (order-independent)
assert_params(:name, :email)
assert_params(MyOp, :name, :email)

# With types (plain Ruby classes or Literal types)
assert_params(name: String, email: String)
assert_params(MyOp, name: String)
```

### assert_accepts_param

```ruby
assert_accepts_param(:name)             # subset check — param exists
assert_accepts_param(MyOp, :name)
```

### assert_success_type

```ruby
assert_success_type(String)
assert_success_type(MyOp, Dex::RefType.new(User))
```

Note: Outside the operation class body, use `Dex::RefType.new(Model)` instead of `_Ref(Model)`.

### assert_error_codes

```ruby
assert_error_codes(:not_found, :invalid)        # exhaustive, order-independent
assert_error_codes(MyOp, :not_found, :invalid)
```

### assert_contract

```ruby
assert_contract(params: [:name, :email], success: String, errors: [:invalid])
assert_contract(MyOp, params: { name: String }, errors: [:invalid])
```

---

## Param Validation Assertions

### assert_invalid_params

```ruby
assert_invalid_params(name: 123)          # asserts Literal::TypeError on construction
assert_invalid_params(MyOp, name: 123)
```

### assert_valid_params

```ruby
assert_valid_params(name: "Alice")        # asserts no error (doesn't perform)
assert_valid_params(MyOp, name: "Alice")
```

---

## Async Assertions

Requires `ActiveJob::TestHelper` included in test class.

```ruby
assert_enqueues_operation(name: "Alice")              # subject
assert_enqueues_operation(MyOp, name: "Alice")        # explicit
assert_enqueues_operation(MyOp, name: "A", queue: "low")  # with queue

refute_enqueues_operation { do_something }            # no jobs enqueued in block
```

---

## Transaction Assertions

```ruby
assert_rolls_back(User) { op.new(bad: true).call }   # raises + count unchanged
assert_commits(User) { op.new(good: true).call }     # count increases
```

---

## Batch Assertions

```ruby
assert_all_succeed(params_list: [{ x: 1 }, { x: 2 }])
assert_all_succeed(MyOp, params_list: [{ x: 1 }, { x: 2 }])

assert_all_fail(code: :invalid, params_list: [{ x: -1 }, { x: -2 }])
assert_all_fail(MyOp, code: :invalid, params_list: [{ x: -1 }])
```

---

## Stubbing

Replaces an operation entirely within a block. Bypasses all wrappers.

```ruby
stub_operation(MyOp, returns: "fake") do
  result = MyOp.new(name: "x").call   # => "fake"
end
# Outside block: real behavior restored

stub_operation(MyOp, error: :not_found) do
  MyOp.new.call  # raises Dex::Error(code: :not_found)
end

stub_operation(MyOp, error: { code: :fail, message: "oops" }) do
  # raises Dex::Error with code and message
end
```

**Key behaviors:**
- Stubs bypass `perform` and all wrappers entirely
- Stubs are NOT recorded in TestLog
- Stubs work transparently with `.safe.call`
- Stubs are cleaned up in `ensure` (safe against exceptions)
- `stub_operation` requires a block

---

## Spying

Observes real execution without modifying behavior.

```ruby
spy_on_operation(MyOp) do |spy|
  MyOp.call(name: "Alice")
  MyOp.call(name: "Bob")

  spy.called?                    # => true
  spy.called_once?               # => false
  spy.call_count                 # => 2
  spy.last_result                # => Ok or Err
  spy.called_with?(name: "Bob") # => true (subset match)
  spy.calls                     # => array of TestLog entries
end
```

**Key behaviors:**
- Real execution happens (no stubbing)
- Only sees calls made after spy creation
- Only sees calls for the specified class

---

## TestLog

Global activity log recording all operation calls.

```ruby
Dex::TestLog.calls       # => array of Entry objects
Dex::TestLog.size        # => Integer
Dex::TestLog.empty?      # => Boolean
Dex::TestLog.clear!      # reset (automatic in setup)

# Find entries by class and params
Dex::TestLog.find(MyOp)                  # => [Entry, ...]
Dex::TestLog.find(MyOp, name: "Alice")   # => [Entry, ...]

# Human-readable summary (useful in failure messages)
Dex::TestLog.summary     # => "Operations called (2):\n  1. MyOp [OK] 1.2ms\n..."
```

### Entry fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String` | Always `"Operation"` |
| `name` | `String` | Class name |
| `operation_class` | `Class` | The operation class |
| `params` | `Hash` | Prop values |
| `result` | `Ok` or `Err` | Wrapped result |
| `duration` | `Float` | Seconds |
| `caller_location` | `Thread::Backtrace::Location` | Call site |

---

## Complete Test Example

```ruby
class CreateUserTest < Minitest::Test
  include Dex::TestHelpers

  testing CreateUser

  def setup
    super
    # ... test database setup
  end

  # Contract
  def test_contract
    assert_params(:name, :email)
    assert_success_type(Dex::RefType.new(User))
    assert_error_codes(:invalid_email, :duplicate)
  end

  # Happy path
  def test_creates_user
    result = call_operation(name: "Alice", email: "a@b.com")
    assert_ok(result) { |user| assert_equal "Alice", user.name }
  end

  # One-liner
  def test_succeeds
    assert_operation(name: "Alice", email: "a@b.com")
  end

  # Error cases
  def test_rejects_bad_email
    assert_operation_error(:invalid_email, name: "A", email: "bad")
  end

  # Batch
  def test_rejects_all_bad_emails
    assert_all_fail(
      code: :invalid_email,
      params_list: [
        { name: "A", email: "" },
        { name: "B", email: "no-at" }
      ]
    )
  end

  # Stubbing a dependency
  def test_sends_welcome_email
    stub_operation(SendWelcomeEmail, returns: true) do
      call_operation!(name: "Alice", email: "a@b.com")
    end
  end

  # Spying
  def test_calls_welcome_email
    spy_on_operation(SendWelcomeEmail) do |spy|
      call_operation!(name: "Alice", email: "a@b.com")
      assert spy.called_once?
      assert spy.called_with?(email: "a@b.com")
    end
  end
end
```
