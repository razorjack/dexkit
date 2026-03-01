# Error Handling

Operations provide structured error handling through `error!`, `success!`, `assert!`, and `rescue_from`. All of these integrate with transactions (errors roll back), safe mode (errors become `Err`), and recording.

## error!

Halts execution and raises `Dex::Error` to the caller. If a transaction is active, it's rolled back.

```ruby
class CreateUser < Dex::Operation
  prop :email, String

  def perform
    error!(:email_taken, "This email is already in use") if User.exists?(email: email)
    User.create!(email: email)
  end
end
```

The full signature:

```ruby
error!(code, message = nil, details: nil)
```

- **code** (Symbol) — a machine-readable error identifier
- **message** (String) — optional human-readable description; defaults to the code as a string
- **details** (Hash) — optional structured data about the error

```ruby
error!(:validation_failed, "Invalid input", details: { field: "email", reason: "bad format" })
```

The caller receives a `Dex::Error` with `.code`, `.message`, and `.details`:

```ruby
begin
  CreateUser.call(email: "taken@example.com")
rescue Dex::Error => e
  e.code     # => :email_taken
  e.message  # => "This email is already in use"
  e.details  # => nil
end
```

## success!

Halts execution with a successful result. The transaction is committed. Code after `success!` is never reached.

```ruby
class ProcessPayment < Dex::Operation
  prop :amount, Integer

  def perform
    return error!(:invalid_amount) if amount <= 0

    charge = Gateway.charge(amount)
    success!(charge_id: charge.id, status: "paid")

    # never reached
  end
end

result = ProcessPayment.call(amount: 100)
# => { charge_id: "ch_123", status: "paid" }
```

You can pass a positional value, keyword arguments (becomes a Hash), or nothing:

```ruby
success!(42)                          # returns 42
success!(name: "Alice", age: 30)     # returns { name: "Alice", age: 30 }
success!                              # returns nil
```

## assert!

A guard that returns the value if truthy, or calls `error!` if falsy. Perfect for "find or fail" patterns:

```ruby
class ShowUser < Dex::Operation
  prop :user_id, Integer

  def perform
    # Block form — evaluate and guard in one step
    user = assert!(:not_found) { User.find_by(id: user_id) }
    user.as_json
  end
end
```

Two forms are supported:

```ruby
# Block form (preferred) — evaluates the block, errors if nil/false
user = assert!(:not_found) { User.find_by(id: user_id) }

# Value form — guards an already-evaluated value
user = User.find_by(id: user_id)
assert!(user, :not_found)
```

Both call `error!(code)` when the value is falsy, which rolls back the transaction and raises `Dex::Error`.

## Declared error codes

You can declare which error codes an operation is allowed to raise. This catches typos and documents intent:

```ruby
class CreateUser < Dex::Operation
  error :email_taken, :invalid_email

  def perform
    error!(:email_takn)  # => ArgumentError: Undeclared error code: :email_takn
  end
end
```

When error codes are declared, calling `error!` with an undeclared code raises `ArgumentError` immediately — a programming mistake caught at runtime. If no codes are declared, any code is allowed.

See also [Contracts](/operation/contracts) for introspecting declared errors.

## rescue_from

Maps third-party exceptions to structured `Dex::Error` codes. No more boilerplate `begin/rescue/error!` blocks:

```ruby
class ChargeCard < Dex::Operation
  rescue_from Stripe::CardError, as: :card_declined
  rescue_from Stripe::RateLimitError, as: :rate_limited
  rescue_from Stripe::APIError, as: :provider_error, message: "Stripe is unavailable"

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
- `Dex::Error` (from `error!`) passes through untouched — `rescue_from` never intercepts it
- Unregistered exceptions propagate normally
- Works naturally with `.safe`, transactions, and recording
- Handlers inherit from parent classes; later declarations take priority

```ruby
result = ChargeCard.new(amount: 100).safe.call
case result
in Dex::Err(code: :card_declined)
  notify_user(result.message)
in Dex::Err(code: :provider_error)
  retry_later
end
```

## Dex::Error

All operation errors are `Dex::Error` instances. They support pattern matching:

```ruby
begin
  CreateUser.call(email: "taken@example.com")
rescue Dex::Error => e
  case e
  in { code: :email_taken }
    flash[:error] = "Email already registered"
  in { code: :invalid_email, message: }
    flash[:error] = message
  end
end
```
