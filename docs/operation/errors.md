---
description: Dex::Operation error handling — declare error codes, halt with error!, rescue exceptions, and let transactions roll back automatically.
---

# Error Handling

Operations provide structured error handling through `error!`, `success!`, and `rescue_from`. All of these integrate with transactions (errors roll back), [Ok / Err](/operation/safe-mode) (errors become `Err`), and recording.

## error!

Halts execution and raises `Dex::Error` to the caller. If a transaction is active, it's rolled back.

```ruby
class Employee::Onboard < Dex::Operation
  prop :email, String

  def perform
    error!(:email_taken, "This email is already in use") if Employee.exists?(email: email)
    Employee.create!(email: email)
  end
end
```

The full signature:

```ruby
error!(code, message = nil, details: nil)
```

- **code** (Symbol) – a machine-readable error identifier
- **message** (String) – optional human-readable description; defaults to the code as a string
- **details** (Hash) – optional structured data about the error

```ruby
error!(:validation_failed, "Invalid input",
  details: { field: "email", reason: "bad format" })
```

The caller receives a `Dex::Error` with `.code`, `.message`, and `.details`:

```ruby
begin
  Employee::Onboard.call(email: "taken@example.com")
rescue Dex::Error => e
  e.code     # => :email_taken
  e.message  # => "This email is already in use"
  e.details  # => nil
end
```

## success!

Halts execution with a successful result. The transaction is committed. Code after `success!` is never reached.

```ruby
class Order::Charge < Dex::Operation
  prop :amount, Integer

  def perform
    return error!(:invalid_amount) if amount <= 0

    charge = Stripe::Charge.create(amount: amount)
    success!(charge_id: charge.id, status: "paid")

    # never reached
  end
end

result = Order::Charge.call(amount: 100)
# => { charge_id: "ch_123", status: "paid" }
```

You can pass a positional value, keyword arguments (becomes a Hash), or nothing:

```ruby
success!(42)                          # returns 42
success!(name: "Alice", age: 30)     # returns { name: "Alice", age: 30 }
success!                              # returns nil
```

## Declared error codes

You can declare which error codes an operation is allowed to raise. This catches typos and documents intent:

```ruby
class Employee::Onboard < Dex::Operation
  error :email_taken, :invalid_email

  def perform
    error!(:email_takn)  # => ArgumentError: Undeclared error code: :email_takn
  end
end
```

When error codes are declared, calling `error!` with an undeclared code raises `ArgumentError` immediately – a programming mistake caught at runtime. If no codes are declared, any code is allowed.

See also [Contracts](/operation/contracts) for introspecting declared errors.

## rescue_from

Maps third-party exceptions to structured `Dex::Error` codes. No more boilerplate `begin/rescue/error!` blocks:

```ruby
class Order::Charge < Dex::Operation
  rescue_from Stripe::CardError, as: :card_declined
  rescue_from Stripe::RateLimitError, as: :rate_limited
  rescue_from Stripe::APIError,
    as: :provider_error, message: "Stripe is unavailable"

  def perform
    Stripe::Charge.create(amount: amount, source: token)
  end
end
```

Multiple exception classes can share the same code:

```ruby
rescue_from Net::OpenTimeout, Net::ReadTimeout, as: :timeout
```

### Options

| Option | Required | Description |
|---|---|---|
| `as:` | yes | The `Dex::Error` code (Symbol) |
| `message:` | no | Overrides the original exception's message |

### Behavior

- The original exception is available in `details[:original]`
- `Dex::Error` (from `error!`) passes through untouched – `rescue_from` never intercepts it
- Unregistered exceptions propagate normally
- Works naturally with `.safe`, transactions, and recording
- Handlers inherit from parent classes; later declarations take priority

```ruby
include Dex::Match

result = Order::Charge.new(amount: 100).safe.call
case result
in Err(code: :card_declined)
  notify_user(result.message)
in Err(code: :provider_error)
  retry_later
end
```

## Dex::Error

All operation errors are `Dex::Error` instances. They support pattern matching:

```ruby
begin
  Employee::Onboard.call(email: "taken@example.com")
rescue Dex::Error => e
  case e
  in { code: :email_taken }
    flash[:error] = "Email already registered"
  in { code: :invalid_email, message: }
    flash[:error] = message
  end
end
```

## Dex::OperationFailed

Raised by [`wait`/`wait!`](/operation/async#speculative-sync-wait-wait) when an async operation crashed with an infrastructure failure (record status `"failed"`). Inherits from `StandardError`, not `Dex::Error` – crashes are categorically different from business errors.

```ruby
begin
  ticket.wait!(3.seconds)
rescue Dex::OperationFailed => e
  e.operation_name    # => "Order::Fulfill"
  e.exception_class   # => "RuntimeError"
  e.exception_message # => "connection refused"
end
```

## Dex::Timeout

Raised by [`wait!`](/operation/async#wait-strict-mode-value-or-exception) when the timeout expires without the operation completing. Inherits from `StandardError`, not `Dex::Error`.

```ruby
begin
  ticket.wait!(3.seconds)
rescue Dex::Timeout => e
  e.timeout        # => 3.0
  e.ticket_id      # => "op_01J5..."
  e.operation_name # => "Order::Fulfill"
end
```

The three exception types are categorically distinct:

| Exception | Represents | Inherits |
|---|---|---|
| `Dex::Error` | Business error (`error!`) | `StandardError` |
| `Dex::OperationFailed` | Infrastructure crash | `StandardError` |
| `Dex::Timeout` | Wait deadline exceeded | `StandardError` |

`rescue Dex::Error` never catches crashes or timeouts.
