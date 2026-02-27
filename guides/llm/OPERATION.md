# Dex::Operation — LLM Reference

**Purpose:** This file documents all features of `Dex::Operation` for AI coding agents. Copy this to your app's operations directory (e.g., `app/operations/CLAUDE.md` or `app/operations/AGENTS.md`) so agents know the full API when implementing operations.

**What it is:** A base class for service objects/operations in Ruby/Rails applications. Provides typed parameters, typed results, error handling, transactions, background jobs, and execution recording.

---

## Quick Start

```ruby
class CreateUser < Dex::Operation
  params do
    attribute :email, Types::String
    attribute :name, Types::String
  end

  result do
    attribute :user_id, Types::Integer
  end

  def perform
    user = User.create!(email: email, name: name)
    { user_id: user.id }
  end
end

# Call it
CreateUser.new(email: "test@example.com", name: "Test").call
# => #<CreateUser::Result user_id=123>
```

---

## Typed Parameters

Define input parameters with types via `params do ... end`. Uses Dry::Struct under the hood.

```ruby
class MyOperation < Dex::Operation
  params do
    attribute :name, Types::String
    attribute :count, Types::Integer.default(1)
    attribute :optional_field, Types::String.optional
    attribute :user, Types::Record(User)  # See Types::Record section
  end

  def perform
    name    # Direct access (delegated by default)
    count
    params.name  # params accessor also available
  end
end

# Call with keyword arguments
MyOperation.new(name: "test", count: 5).call
```

**Key facts:**
- Parameters are validated and coerced on initialization
- Access directly via attribute name (e.g., `name`) — delegated by default
- `params` accessor also available for explicit access or struct methods (`.as_json`, `.to_h`)
- Supports all Dry::Types features (defaults, optional, constraints)
- Invalid params raise `Dry::Struct::Error` on initialization

**Delegation options:**
```ruby
params { ... }                              # delegates all (default)
params(delegate: true) { ... }             # delegates all (explicit)
params(delegate: false) { ... }            # no delegation
params(delegate: :email) { ... }           # delegate only :email
params(delegate: [:email, :name]) { ... }  # delegate specific list
```

---

## Typed Results

Define output schema via `result do ... end`. When `perform` returns a Hash and a result schema exists, the Hash is automatically wrapped into a typed Result struct.

```ruby
class MyOperation < Dex::Operation
  result do
    attribute :user_id, Types::Integer
    attribute :status, Types::String
  end

  def perform
    { user_id: 1, status: "created" }  # Hash return
  end
end

result = MyOperation.new.call
result.user_id  # => 1
result.status   # => "created"
result.class    # => MyOperation::Result (Dry::Struct)
```

**Key facts:**
- Only wraps Hash returns — other types (String, Integer, nil) pass through unchanged
- Without a result schema, Hash returns remain plain Hashes
- Result struct supports all Dry::Struct features

---

## Flow Control (`error!` / `success!`)

Both methods halt execution immediately — code after them is never reached. They work from `perform` and any methods called from it (non-local exit).

### `error!(code, message = nil, details: nil)`

Halt with failure. Rolls back the transaction. Raises `Dex::Error` to the caller.

```ruby
def perform
  error!(:not_found, "User not found")
  error!(:validation_failed, "Invalid input", details: { field: "email" })
  error!(:unauthorized)  # message defaults to "unauthorized"
end
```

### `success!(value = nil, **attrs)`

Halt with success. Commits the transaction. Returns the value (wrapped by result schema if defined).

```ruby
def perform
  success!(42)                        # positional value
  success!(name: "John", age: 30)    # keyword args → Hash, wrapped by result schema if present
  success!                            # returns nil
end
```

**Dex::Error structure:**
- `code` — Symbol identifying error type
- `message` — String description (defaults to code.to_s)
- `details` — Arbitrary object (typically Hash) with additional context

**Pattern matching supported:**
```ruby
begin
  MyOperation.new.call
rescue Dex::Error => e
  case e
  in {code: :not_found, message:}
    # handle not found
  in {code: :validation_failed, details: {field:}}
    # handle validation
  end
end
```

**Key facts:**
- Both halt immediately, stopping execution (non-local exit via `throw`/`catch`)
- `error!` triggers transaction rollback; `success!` commits
- `error!` skips `after` callbacks and `around` post-yield; `success!` runs both
- Both skip operation recording
- Both work from `before` callbacks and helper methods
- `success!` with kwargs and a result schema wraps the value into the typed Result struct

---

## Rescue Mapping

Map third-party exceptions to structured `Dex::Error` codes via `rescue_from`. Eliminates `begin/rescue/error!` boilerplate.

```ruby
class ChargeCard < Dex::Operation
  rescue_from Stripe::CardError,      as: :card_declined
  rescue_from Stripe::RateLimitError, as: :rate_limited
  rescue_from Stripe::APIError,       as: :provider_error, message: "Stripe is down"
  rescue_from Net::OpenTimeout, Net::ReadTimeout, as: :timeout  # multiple classes in one call

  def perform
    Stripe::Charge.create(amount: amount, source: token)
  end
end
```

**Options:**

| Option | Required | Description |
|--------|----------|-------------|
| `as:` | Yes | Symbol code for the resulting `Dex::Error` |
| `message:` | No | Overrides original exception message; defaults to exception's own message |

**Behavior:**
- Original exception preserved in `err.details[:original]`
- `Dex::Error` (from `error!`) passes through untouched — never re-wrapped
- Unregistered exceptions propagate normally
- Later `rescue_from` declarations take precedence (more specific wins)
- Subclass exceptions match a handler registered for a parent class
- Exceptions from `before`/`around` callbacks are also caught

**Inheritance:**
```ruby
class Base < Dex::Operation
  rescue_from StandardError, as: :general_error
end

class Child < Base
  rescue_from ArgumentError, as: :bad_argument  # inherits Base handlers, adds own
end
```
Parent handlers run first; child's more specific handlers shadow them for matching types.

**Integration with `.safe`:**
```ruby
result = ChargeCard.new(amount: 100, token: "tok_xxx").safe.call
case result
in Dex::Err(code: :card_declined, details: {original:})
  puts "Card declined: #{original.message}"
in Dex::Err(code: :timeout)
  puts "Provider timed out"
end
```

**Key facts:**
- Converted `Dex::Error` triggers transaction rollback (correct — operation failed)
- Recording is skipped (consistent with `error!` behavior)
- `rescue_from` with no exception classes raises `ArgumentError`

---

## Safe Execution (Ok/Err)

Use `.safe.call` to wrap results in monadic `Ok`/`Err` types instead of raising exceptions. Enables functional error handling and pattern matching.

```ruby
outcome = MyOperation.new(value: 5).safe.call

if outcome.ok?
  outcome.value      # Access result
  outcome.user_id    # Ok delegates to wrapped value
else
  outcome.error?     # => true
  outcome.code       # Error code
  outcome.message    # Error message
  outcome.details    # Error details
  outcome.value!     # Re-raises the original Dex::Error
end
```

**Ok class (`Dex::Ok`):**
- `ok?` → `true`, `error?` → `false`
- `value` / `value!` → returns wrapped value
- Delegates unknown methods to wrapped value (transparent access)
- Supports pattern matching

**Err class (`Dex::Err`):**
- `ok?` → `false`, `error?` → `true`
- `value` → `nil`, `value!` → re-raises `Dex::Error`
- `code`, `message`, `details` → delegates to error
- `error` → returns raw `Dex::Error`
- Supports pattern matching

**Pattern matching:**
```ruby
case MyOperation.new(id: 123).safe.call
in Dex::Ok(user_id: id)
  puts "Created user #{id}"
in Dex::Err(code: :not_found)
  puts "Not found"
in Dex::Err(code: :validation_failed, details: {field:})
  puts "Field #{field} invalid"
end
```

**Dex::Match module:** Include `Dex::Match` to use `Ok`/`Err` without `Dex::` prefix:
```ruby
include Dex::Match

case outcome
in Ok(user:)
  # ...
in Err(code:)
  # ...
end
```

**Key facts:**
- Only catches `Dex::Error` — other exceptions (RuntimeError, ActiveRecord errors) propagate normally
- Works with result schemas — Ok wraps the typed Result struct
- Ok method delegation makes `outcome.field` work without unwrapping

---

## Async Execution

Enqueue operations as background jobs via `.async.call`. Requires ActiveJob.

```ruby
# Enqueue immediately
MyOperation.new(user_id: 123).async.call

# With queue
MyOperation.new(user_id: 123).async(queue: "mailers").call

# Delayed execution
MyOperation.new(user_id: 123).async(in: 5.minutes).call
MyOperation.new(user_id: 123).async(at: 1.hour.from_now).call
```

**Class-level defaults:**
```ruby
class SendEmailOp < Dex::Operation
  async queue: "mailers"
  # Equivalent to: set :async, queue: "mailers"
end

SendEmailOp.new(...).async.call  # Uses "mailers" queue
SendEmailOp.new(...).async(queue: "urgent").call  # Overrides to "urgent"
```

**Supported options:**
- `queue:` — ActiveJob queue name
- `in:` — Delay in seconds
- `at:` — Schedule at specific Time

**Type-safe serialization:** Params are serialized via `as_json` and automatically coerced back to typed equivalents on deserialization. No need to change types when adding `.async`.

| Type | Serialized as | Deserialized via |
|------|--------------|-----------------|
| `Date` | `"2025-06-15"` | `Date.parse` |
| `Time` | `"2025-06-15 10:30:00 UTC"` | `Time.parse` |
| `DateTime` | `"2025-06-15T10:30:00+00:00"` | `DateTime.parse` |
| `BigDecimal` | `"99.99"` | `BigDecimal()` |
| `Symbol` | `"active"` | `String#to_sym` |
| `Record(Model)` | `123` (ID) | `Model.find(id)` |

Works with `.optional` and `Array.of(...)` types. Direct (non-async) calls remain strict — no implicit coercion.

**Key facts:**
- Params serialized via `as_json` (Record → ID, Date → string, etc.)
- Non-serializable params raise `ArgumentError` at enqueue time
- Job instantiates operation class and calls `call` synchronously in worker
- Runtime options merge with and override class-level defaults
- Raises `LoadError` if ActiveJob is not available

### Async + Recording Integration

When both async and recording are enabled (with params recording), Dexkit automatically uses a **record-based strategy** that stores only the record ID in the job payload instead of the full params hash. This reduces Redis memory usage for operations with large payloads.

**Strategy selection (automatic — no new DSL):**

| Condition | Job class | Redis payload |
|-----------|-----------|---------------|
| Recording enabled + params recorded | `RecordJob` | `{ class_name:, record_id: }` |
| Everything else | `DirectJob` | `{ class_name:, params: {} }` |

`DirectJob` is used when: no recording configured, `record false`, `record params: false`, or anonymous class.

**Status tracking:** The record's `status` field tracks the lifecycle:

| Status | Set by | When |
|--------|--------|------|
| `pending` | `AsyncProxy` | At enqueue time |
| `running` | `RecordJob` | Before `op.call` (fail-soft) |
| `done` | `RecordWrapper` | After successful `perform` |
| `failed` | `RecordJob` | On exception (fail-soft) |

Sync calls and `DirectJob` calls set `status: "done"` when the column exists.

**Error field:** On failure, the `error` column stores:
- `Dex::Error` → `error.code.to_s` (e.g., `"not_found"`)
- Other exceptions → `exception.class.name` (e.g., `"RuntimeError"`)

**Migration columns:**
```ruby
t.string :status   # Optional: pending/running/done/failed
t.string :error    # Optional: error code or exception class name
```

Both columns are optional — `safe_attributes` silently skips missing columns.

**Key facts:**
- Strategy selected automatically based on recording config
- Record created fail-fast (exception propagates if DB down)
- Status updates are fail-soft (swallowed + logged)
- If record deleted before job runs → `RecordNotFound` raised
- If enqueue fails → record cleaned up (best-effort)
- `Dex::Operation::Job` is a backward-compatible alias for `DirectJob`

---

## Callbacks

Hook into the operation lifecycle. Callbacks run **inside** the transaction boundary (errors rollback).

```ruby
class ProcessOrder < Dex::Operation
  before :validate_stock           # symbol — calls method on instance
  before -> { log("starting") }    # lambda — instance_exec'd
  before { log("starting") }       # block — instance_exec'd

  after :send_confirmation         # runs after perform succeeds
  after -> { notify }

  around :with_timing              # symbol — method uses yield
  around ->(cont) { cont.call }    # proc — receives continuation callable

  def validate_stock
    error!(:out_of_stock) unless in_stock?  # has access to params, delegated attrs, error!, etc.
  end

  def with_timing
    start = Time.now
    yield
    puts Time.now - start
  end
end
```

**DSL methods:**

| Method | Accepts | Description |
|--------|---------|-------------|
| `before(sym_or_callable = nil, &block)` | Symbol, Proc/lambda, or block | Runs before `perform` |
| `after(sym_or_callable = nil, &block)` | Symbol, Proc/lambda, or block | Runs after `perform` succeeds |
| `around(sym_or_callable = nil, &block)` | Symbol, Proc/lambda, or block | Wraps the full lifecycle |

**Execution order:** `around` wraps everything → `before` callbacks → user `perform` → `after` callbacks

**Key behaviors:**
- `before` calling `error!` stops execution — `perform` and `after` never run
- `after` is skipped if `perform` raises or calls `error!`; runs on normal return and `success!`
- `around` with a symbol: the method receives a block, call `yield` to proceed
- `around` with a proc/lambda: receives continuation as first argument, call `cont.call` to proceed
- If `around` callback doesn't yield/call continuation, `perform` never runs (circuit breaker pattern)
- Multiple around callbacks nest (first registered = outermost)
- Inheritance: parent callbacks run first, then child callbacks
- Child class callbacks don't affect parent class

**Inheritance example:**
```ruby
class Base < Dex::Operation
  before { log("base") }
end

class Child < Base
  before { log("child") }
  # Order: base → child → perform
end
```

---

## Transactions

Operations run inside database transactions by default. All changes rollback on any error.

```ruby
class CreateOrder < Dex::Operation
  def perform
    Order.create!(...)
    LineItem.create!(...)
    # Both rolled back if error occurs
  end
end
```

**Disable transactions:**
```ruby
class ReadOnlyOp < Dex::Operation
  transaction false
end
```

**Adapter override:**
```ruby
class MongoidOp < Dex::Operation
  transaction :mongoid
  # Or: transaction adapter: :mongoid
end
```

**Global configuration:**
```ruby
Dex.configure do |config|
  config.transaction_adapter = :active_record  # default
  # or
  config.transaction_adapter = :mongoid
end
```

**Available adapters:** `:active_record`, `:mongoid`

**Key facts:**
- Enabled by default with `:active_record` adapter
- Raising any exception (including `error!`) triggers rollback
- Nested operations share outer transaction
- Recording saves happen inside transaction (see Recording section)
- Can re-enable in child class if parent disabled: `transaction true`

---

## Advisory Locking

Wrap operations in database advisory locks for mutual exclusion. Uses the [`with_advisory_lock`](https://github.com/ClosureTree/with_advisory_lock) gem (optional runtime dependency — not in gemspec).

```ruby
class ProcessPayment < Dex::Operation
  params do
    attribute :charge_id, Types::String
  end

  advisory_lock { "pay:#{charge_id}" }  # dynamic key

  def perform
    # Only one instance with same charge_id runs at a time
  end
end
```

**DSL forms:**
```ruby
advisory_lock { "pay:#{charge_id}" }           # dynamic block (instance_exec'd)
advisory_lock(timeout: 5) { "pay:#{charge_id}" } # with timeout (seconds)
advisory_lock "generate-daily-report"           # static string key
advisory_lock "report", timeout: 5              # static + timeout
advisory_lock                                   # class name as key
advisory_lock :compute_lock_key                 # symbol → calls instance method
```

**Options:**

| Option | Type | Description |
|--------|------|-------------|
| `timeout:` | Integer | Seconds to wait for lock; raises on timeout |

**On timeout:** Raises `Dex::Error.new(:lock_timeout, "Could not acquire advisory lock: <key>")`.

**Key facts:**
- Opt-in (disabled by default) — must declare `advisory_lock` to enable
- Wraps **outside** the transaction boundary (lock acquired before transaction starts)
- Settings inherit from parent class; child can override
- Raises `LoadError` if `with_advisory_lock` gem is not loaded
- Works with `.safe` — timeout returns `Err(code: :lock_timeout)`
- Do **not** add `with_advisory_lock` to your gemspec — it's an optional runtime dependency

---

## Recording

Record operation execution to database. Requires configuring `Dex.record_class`.

**Setup:**
```ruby
# config/initializers/dexkit.rb
Dex.configure do |config|
  config.record_class = OperationRecord  # ActiveRecord or Mongoid model
end

# Migration for OperationRecord
create_table :operation_records do |t|
  t.string :name            # Required: operation class name
  t.jsonb :params           # Optional: serialized params
  t.jsonb :response         # Optional: serialized result
  t.string :status          # Optional: pending/running/done/failed (for async+recording)
  t.string :error           # Optional: error code on failure (for async+recording)
  t.datetime :performed_at  # Optional: execution timestamp
  t.timestamps
end
```

**Granular control:**
```ruby
class SensitiveOp < Dex::Operation
  record false                     # Disable entirely
end

class LargeResponseOp < Dex::Operation
  record response: false           # Record params only
end

class AuditOp < Dex::Operation
  record params: false             # Record response only
end
```

**What gets recorded:**
- `name` — Operation class name (always)
- `params` — Serialized via `params.as_json` (if `params: true`, default)
- `response` — Serialized result (if `response: true`, default)
- `performed_at` — Execution timestamp (if column exists)

**Response serialization:**
- Result with schema → calls `.as_json` on Result struct
- Hash without schema → stored as-is
- Primitive (Integer, String) → wrapped as `{ value: result }`
- `nil` → stored as nil
- `Types::Record` attributes → serialized as IDs (not full objects)

**Key facts:**
- Recording happens INSIDE transaction (rolled back on error)
- `error!` prevents recording (error raised before save)
- Missing columns silently ignored (minimal table with just `name` works)
- Recording failures silently swallowed (logged if Rails available)
- Anonymous operation classes cannot be recorded

---

## Settings

Generic class-level configuration system. Foundation for all other features.

```ruby
class MyOp < Dex::Operation
  set :custom_key, option1: "value", option2: 123

  def self.my_custom_config
    settings_for(:custom_key)  # => { option1: "value", option2: 123 }
  end
end
```

**Merging:** Multiple `set` calls for same key merge options:
```ruby
set :async, queue: "low"
set :async, priority: 5
# settings_for(:async) => { queue: "low", priority: 5 }
```

**Inheritance:** Child classes inherit parent settings. Child can override:
```ruby
class Parent < Dex::Operation
  set :async, queue: "default", priority: 5
end

class Child < Parent
  set :async, queue: "urgent"  # Overrides queue, inherits priority
end
# Child.settings_for(:async) => { queue: "urgent", priority: 5 }
```

**Key facts:**
- All feature DSLs (`async`, `transaction`, `record`) use `set` under the hood
- Unset keys return `{}`
- Different keys are independent

---

## Types::Record(Model)

Parameterized type for ActiveRecord/Mongoid model instances. Accepts instances or IDs, automatically coerces IDs to records.

**Setup (required):**
```ruby
module Types
  include Dry.Types(default: :nominal)
  extend Dex::Types::Extension  # Adds Record() constructor
end
```

**Usage:**
```ruby
class SendEmail < Dex::Operation
  params do
    attribute :user, Types::Record(User)
    attribute :avatar, Types::Record(Avatar).optional
  end

  result do
    attribute :user, Types::Record(User)
  end

  def perform
    # user is a User instance (coerced from ID if passed as ID)
    EmailService.send(user.email)
    { user: user }
  end
end

# All of these work:
SendEmail.new(user: User.find(1)).call   # Instance
SendEmail.new(user: 1).call              # Integer ID
SendEmail.new(user: "1").call            # String ID
SendEmail.new(user: user_instance, avatar: nil).call  # Optional
```

**Lock option:** Use `lock: true` to acquire a row lock (`SELECT ... FOR UPDATE`) when coercing from ID. Useful inside transactions to prevent concurrent modifications.

```ruby
params do
  attribute :user, Types::Record(User, lock: true)
end
```

When an ID is passed, uses `Model.lock.find(id)`. When an instance is passed directly, no re-locking occurs.

**Coercion behavior:**
- Instance of model class → passes through (no lock, even with `lock: true`)
- `nil` → passes through (use `.optional` to allow nil)
- Integer or String → calls `Model.find(id)` (or `Model.lock.find(id)` with `lock: true`)
- Not found → raises `ActiveRecord::RecordNotFound`

**Serialization:** In `as_json` (used by recording), Record types serialize as the model's ID, not the full object.

```ruby
params.as_json  # => {"user" => 123}  (not full User object)
```

**Key facts:**
- Works in both `params` and `result` blocks
- Supports `.optional` for nullable fields
- Reduces JSON bloat in operation recordings
- All model methods work directly on coerced value

---

## Class-Level DSL Reference

| Method | Purpose | Example |
|--------|---------|---------|
| `params(delegate: true) { ... }` | Define typed input parameters; delegates attrs as methods by default | `params do attribute :name, Types::String end` |
| `result { ... }` | Define typed result schema | `result do attribute :id, Types::Integer end` |
| `before(sym_or_callable = nil, &block)` | Register before callback | `before :validate` / `before { error!(:x) }` |
| `after(sym_or_callable = nil, &block)` | Register after callback | `after :notify` / `after -> { log }` |
| `around(sym_or_callable = nil, &block)` | Register around callback | `around :with_timing` / `around { \|c\| c.call }` |
| `async(**opts)` | Set default async options | `async queue: "mailers"` |
| `transaction(arg)` | Configure transactions | `transaction false` / `transaction :mongoid` |
| `advisory_lock(key = nil, **opts, &block)` | Configure advisory locking | `advisory_lock "key"` / `advisory_lock { "pay:#{id}" }` |
| `record(arg)` | Configure recording | `record false` / `record params: false` |
| `rescue_from(*classes, as:, message: nil)` | Map exceptions to Dex::Error | `rescue_from Stripe::CardError, as: :card_declined` |
| `set(key, **opts)` | Store arbitrary settings | `set :custom, value: 123` |
| `settings_for(key)` | Retrieve settings | `settings_for(:async)` |

---

## Instance-Level API Reference

| Method | Returns | Description |
|--------|---------|-------------|
| `params` | Typed params object | Access input parameters (also available as direct methods by default) |
| `call` | Result | Public entry point — invokes `perform` through the wrapper chain |
| `perform` | Result | Implement this — private, called by `call` |
| `error!(code, msg, details:)` | (halts) | Halt with failure — rolls back transaction, raises Dex::Error to caller |
| `success!(value, **attrs)` | (halts) | Halt with success — commits transaction, returns value |
| `safe` | SafeProxy | Returns proxy for Ok/Err execution via `.safe.call` |
| `async(**opts)` | AsyncProxy | Returns proxy for background execution via `.async.call` |

---

## Key Behaviors (Non-Obvious)

1. **Params delegated by default** — All param attributes are accessible directly (e.g., `name` instead of `params.name`). The `params` accessor is still available. Disable with `params(delegate: false)` or delegate selectively with `params(delegate: :field)` or `params(delegate: [:a, :b])`.

2. **Safe only catches `Dex::Error`** — Other exceptions (RuntimeError, ActiveRecord errors) propagate through `.safe.call` without wrapping.

3. **Result wrapping only for Hashes** — If `perform` returns a non-Hash (String, Integer, nil) and a result schema exists, the value passes through unwrapped.

4. **Ok delegates to value** — `ok.user_id` works if `ok.value` responds to `user_id`. No need to unwrap explicitly.

5. **Callbacks run inside transaction** — Errors in callbacks trigger rollback.

6. **Recording happens inside transaction** — When both are enabled, the operation record is rolled back if `perform` raises.

7. **`error!` and `success!` skip recording** — Both halt before recording save. Use normal `return` if you want recording to happen. However, `success!` still runs `after` callbacks and `around` post-yield code; `error!` skips both.

8. **Nested operations share transaction** — If outer operation calls inner operation, both share the transaction. Outer rollback rolls back inner changes.

9. **Missing record columns OK** — Recording filters to only existing columns. A minimal table with just `name` and timestamps works.

10. **Async serializes and coerces params** — Params are serialized via `as_json` and transparently coerced back (Date, Time, BigDecimal, Symbol, Record). Non-serializable params raise `ArgumentError` at enqueue time.

11. **Anonymous classes cannot record** — Operation class must have a name for recording to work.

12. **Settings inherit and merge** — Child classes inherit parent settings. Multiple `set` calls for same key merge (not replace).

13. **`rescue_from` converts to `Dex::Error`** — Mapped exceptions become structured errors, so `.safe`, pattern matching, transactions, and recording all behave consistently with `error!`.

14. **`rescue_from` inheritance** — Child classes inherit parent rescue handlers. Later declarations (child's own) take precedence for the same exception class.

15. **Advisory lock wraps outside transaction** — `advisory_lock` acquires the lock before the transaction starts. On timeout, raises `Dex::Error(:lock_timeout)`. Requires `with_advisory_lock` gem (optional, not in gemspec).

16. **Async + recording auto-optimizes** — When recording is enabled with params, `.async.call` stores only the record ID in Redis (via `RecordJob`) instead of the full params hash. This is automatic — no DSL changes needed. The record tracks `status` (`pending` → `running` → `done`/`failed`) and `error` (code or exception class name).

---

## Global Configuration

```ruby
# config/initializers/dexkit.rb
Dex.configure do |config|
  config.record_class = OperationRecord        # Model for recording (default: nil)
  config.transaction_adapter = :active_record   # :active_record or :mongoid (default: :active_record)
end
```

---

## Full Example

```ruby
class CreateOrder < Dex::Operation
  async queue: "orders"
  transaction true  # Explicit (default anyway)
  record response: false  # Don't record large response

  params do
    attribute :user, Types::Record(User)
    attribute :items, Types::Array.of(Types::Hash)
    attribute :total, Types::Coercible::Decimal
  end

  result do
    attribute :order_id, Types::Integer
    attribute :status, Types::String
  end

  def perform
    order = Order.create!(user: user, total: total)

    items.each do |item|
      order.line_items.create!(item)
    end

    error!(:insufficient_stock) if order.line_items.empty?

    { order_id: order.id, status: "pending" }
  end
end

# Sync execution with error handling
case CreateOrder.new(user: 123, items: [...], total: 99.99).safe.call
in Ok(order_id: id)
  puts "Order #{id} created"
in Err(code: :insufficient_stock)
  puts "Out of stock"
end

# Async execution
CreateOrder.new(user: 123, items: [...], total: 99.99).async.call
```

---

**End of reference.** For the latest features, check the dexkit repository or CHANGELOG.
