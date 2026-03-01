# Dex::Operation — LLM Reference

**Purpose:** This file documents all features of `Dex::Operation` for AI coding agents. Copy this to your app's operations directory (e.g., `app/operations/CLAUDE.md` or `app/operations/AGENTS.md`) so agents know the full API when implementing operations.

**What it is:** A base class for service objects/operations in Ruby/Rails applications. Provides typed properties, success/error contract declarations, error handling, transactions, background jobs, and execution recording.

---

## Quick Start

```ruby
class CreateUser < Dex::Operation
  prop :email, String
  prop :name,  String

  success _Ref(User)  # optional: declare success type
  error :email_taken      # optional: declare error codes

  def perform
    error!(:email_taken) if User.exists?(email: email)
    User.create!(email: email, name: name)
  end
end

# Call it
user = CreateUser.call(email: "test@example.com", name: "Test")
# => User instance
# Use `new(...)` form when chaining modifiers (`.safe.call`, `.async.call`).
```

---

## Properties (Props)

Define input properties directly on the operation class using `prop` and `prop?`.

```ruby
class MyOperation < Dex::Operation
  prop  :name,           String
  prop  :count,          Integer, default: 1
  prop  :user,           _Ref(User)              # See _Ref(Model) section
  prop  :currency,       _Union("USD", "EUR"),   default: "USD"
  prop? :optional_field, String                   # nilable, defaults to nil

  def perform
    name    # Direct reader method
    count
    user    # Coerced User instance
  end
end

# Call with keyword arguments
MyOperation.call(name: "test", count: 5, user: 123)
```

**`prop :name, Type`** — Required property. Raises `Literal::TypeError` if value doesn't match type.

**`prop? :name, Type`** — Optional property. Nilable (accepts nil), defaults to nil. Equivalent to `prop :name, _Nilable(Type), default: nil`.

**Built-in types from Literal::Types** (available as class methods in operation body):

| Constructor | Description | Example |
|-------------|-------------|---------|
| Plain class | Matches with `===` | `String`, `Integer`, `Float`, `Hash`, `Array` |
| `_Integer(range)` | Constrained integer | `_Integer(1..)`, `_Integer(0..100)` |
| `_String(constraints)` | Constrained string | `_String(length: 1..500)` |
| `_Array(type)` | Typed array | `_Array(Integer)`, `_Array(String)` |
| `_Union(*values)` | Enum of values | `_Union("USD", "EUR", "GBP")` |
| `_Nilable(type)` | Nilable wrapper | `_Nilable(String)` |
| `_Ref(Model)` | Model reference (see below) | `_Ref(User)`, `_Ref(Account, lock: true)` |

**Literal types cheat sheet** (types use `===` for validation; all constructors available in operation class body):

```ruby
prop :name,     String                       # any String
prop :count,    Integer                      # any Integer
prop :amount,   Float                        # any Float
prop :amount,   BigDecimal                   # any BigDecimal
prop :data,     Hash                         # any Hash
prop :items,    Array                        # any Array
prop :active,   _Boolean                     # true or false
prop :role,     Symbol                       # any Symbol
prop :count,    _Integer(1..)                # Integer >= 1
prop :count,    _Integer(0..100)             # Integer 0–100
prop :name,     _String(length: 1..255)      # String with length constraint
prop :score,    _Float(0.0..1.0)             # Float in range
prop :tags,     _Array(String)               # Array of Strings
prop :ids,      _Array(Integer)              # Array of Integers
prop :matrix,   _Array(_Array(Integer))      # nested typed arrays
prop :currency, _Union("USD", "EUR", "GBP")  # enum of values
prop :id,       _Union(String, Integer)      # union of types
prop :label,    _Nilable(String)             # String or nil
prop :meta,     _Hash(Symbol, String)        # Hash with typed keys+values
prop :pair,     _Tuple(String, Integer)      # fixed-size typed array
prop :name,     _Frozen(String)              # must be frozen
prop :handler,  _Callable                    # anything responding to .call
prop :handler,  _Interface(:call, :arity)    # responds to listed methods
prop :user,     _Ref(User)                   # Dex-specific: model by instance or ID
prop :account,  _Ref(Account, lock: true)    # Dex-specific: with row lock
prop :title,    String, default: "Untitled"  # default value
prop? :note,    String                       # optional (nilable, default: nil)
```

**Key facts:**
- Properties are validated on initialization via `Literal::TypeError`
- Access directly via property name (e.g., `name`, `user`) — public reader methods
- No `params` accessor or delegation — props ARE reader methods
- Reserved names that cannot be used: `call`, `perform`, `async`, `safe`, `initialize`

---

## Operation Contract (`success` / `error`)

Declare what an operation returns and which errors it can raise. Both are **optional** and purely declarative — they document intent and catch coding mistakes. No wrapping, no struct coercion.

### `success(type)`

Declares the type of the value returned by `perform` on success. **Validates the actual return value at runtime** using `===` — raises `ArgumentError` if `perform` returns a mismatched type. Also affects response serialization in recording (e.g., `_Ref(Model)` → records ID only).

```ruby
class FindUser < Dex::Operation
  success _Ref(User)

  def perform
    User.find(user_id)  # Must return a User instance or nil
  end
end
```

**Validation behavior:**
- `nil` return is always allowed (many operations return nil implicitly)
- `_Ref(Model)` — checks `value.is_a?(ModelClass)`
- Plain classes (`String`, `Integer`, etc.) — checks `value.is_a?(class)`
- Raises `ArgumentError` — same severity as undeclared `error!` codes

Accessible as `MyOp._success_type`. Inherits from parent class.

### `error(*codes)`

Declares which error codes `error!()` may raise. When declared, calling `error!` with an undeclared code raises `ArgumentError` immediately (programming mistake detection).

```ruby
class CreateUser < Dex::Operation
  error :email_taken, :invalid_email

  def perform
    error!(:email_taken) if User.exists?(email: email)
    error!(:surprise)     # => ArgumentError: Undeclared error code
  end
end
```

Without any `error` declaration, any code is accepted (backward compatible). Inherits from parent, child codes are merged and deduplicated. Accessible as `MyOp._declared_errors`.

**Class methods:**
- `MyOp._success_type` — returns declared type or `nil`
- `MyOp._declared_errors` — returns `[Symbol]` (merged with parent, deduped)
- `MyOp._has_declared_errors?` — `true` if any error codes declared

### `.contract` — introspection

Returns a frozen `Dex::Operation::Contract` value object (`Data.define`) aggregating all declared metadata:

```ruby
CreateUser.contract
# => #<data Dex::Operation::Contract
#      params={email: String, name: String},
#      success=_Ref(User),
#      errors=[:email_taken, :invalid_email]>
```

**Fields:**
- `params` → `Hash{Symbol => type}` — declared property names and their types; `{}` if none
- `success` → type or `nil`
- `errors` → `Array<Symbol>`, merged with parent, deduped; `[]` if none

**Behaviour:**
- Frozen (immutable `Data` object)
- Supports pattern matching: `CreateUser.contract => { params:, success:, errors: }`
- `to_h` returns a plain hash
- Inherits from parent class automatically

```ruby
# Pattern matching
CreateUser.contract => { params:, errors: }
errors  # => [:email_taken, :invalid_email]

# Hash conversion
CreateUser.contract.to_h
# => { params: {...}, success: ..., errors: [...] }
```

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

Halt with success. Commits the transaction. Returns the value as-is.

```ruby
def perform
  success!(42)                        # positional value
  success!(name: "John", age: 30)    # keyword args → Hash
  success!                            # returns nil
end
```

### `assert!(code, &block)` / `assert!(value, code)`

Guard against nil/false. Returns the value if truthy; calls `error!(code)` otherwise (rolls back transaction, raises `Dex::Error`).

```ruby
# Block form: error code first, block produces the value
user = assert!(:not_found) { User.find_by(id: user_id) }

# Value form: value first, error code second
assert!(user, :not_found)
```

Both forms respect declared error codes — undeclared code raises `ArgumentError` (same as `error!`). Works with `.safe` modifier.

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
- All three halt immediately, stopping execution (non-local exit via `throw`/`catch`)
- `error!` and `assert!` trigger transaction rollback; `success!` commits
- `error!` and `assert!` skip `after` callbacks and `around` post-yield; `success!` runs both
- `error!` and `assert!` skip operation recording; `success!` records normally
- All work from `before` callbacks and helper methods
- When `error :codes` is declared, `error!` and `assert!` validate the code — undeclared code raises `ArgumentError`
- `assert!` returns the value on success — use the return value to assign in one step

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
- Ok wraps the raw return value (whatever `perform` returned)
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

**Type-safe serialization:** Props are serialized via `as_json` and automatically coerced back to typed equivalents on deserialization. No need to change types when adding `.async`.

| Type | Serialized as | Deserialized via |
|------|--------------|-----------------|
| `Date` | `"2025-06-15"` | `Date.parse` |
| `Time` | `"2025-06-15 10:30:00 UTC"` | `Time.parse` |
| `DateTime` | `"2025-06-15T10:30:00+00:00"` | `DateTime.parse` |
| `BigDecimal` | `"99.99"` | `BigDecimal()` |
| `Symbol` | `"active"` | `String#to_sym` |
| `_Ref(Model)` | `123` (ID) | `Model.find(id)` |

Works with `_Nilable(T)` and `_Array(T)` types. Direct (non-async) calls remain strict — no implicit coercion.

**Key facts:**
- Props serialized via `as_json` (Ref → ID, Date → string, etc.)
- Non-serializable props raise `ArgumentError` at enqueue time
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
    error!(:out_of_stock) unless in_stock?  # has access to props, error!, etc.
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
| `before(sym_or_proc = nil, &block)` | Symbol, Proc/lambda, or block | Runs before `perform` |
| `after(sym_or_proc = nil, &block)` | Symbol, Proc/lambda, or block | Runs after `perform` succeeds |
| `around(sym_or_proc = nil, &block)` | Symbol, Proc/lambda, or block | Wraps the full lifecycle |

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
  config.transaction_adapter = nil  # auto-detect (default)
  # or
  config.transaction_adapter = :mongoid
end
```

**Available adapters:** `nil` (auto-detect, default), `:active_record`, `:mongoid`

**Key facts:**
- Auto-detects adapter (AR → Mongoid); skips if neither loaded. Set explicitly to require.
- Raising any exception (including `error!`) triggers rollback
- Nested operations share outer transaction
- Recording saves happen inside transaction (see Recording section)
- Can re-enable in child class if parent disabled: `transaction true`

---

## Advisory Locking

Wrap operations in database advisory locks for mutual exclusion. Uses the [`with_advisory_lock`](https://github.com/ClosureTree/with_advisory_lock) gem (optional runtime dependency — not in gemspec).

```ruby
class ProcessPayment < Dex::Operation
  prop :charge_id, String

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
  t.jsonb :params           # Optional: serialized props
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
- `params` — Serialized via `_props_as_json` (if `params: true`, default)
- `response` — Serialized result (if `response: true`, default)
- `performed_at` — Execution timestamp (if column exists)

**Response serialization:**
- With `success _Ref(Model)` declared → stored as the model's integer ID
- With `success SomeType` declared → calls `.as_json` on result if available
- Hash without `success` declaration → stored as-is
- Primitive (Integer, String) without `success` → wrapped as `{ value: result }`
- `nil` → stored as nil

**Key facts:**
- Recording happens INSIDE transaction (rolled back on error)
- `error!` and `assert!` prevent recording (transaction rolled back); `success!` records normally
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

## _Ref(Model)

Type constructor for ActiveRecord/Mongoid model instances. Accepts instances or IDs, automatically coerces IDs to records.

**Usage (inside operation class body):**
```ruby
class SendEmail < Dex::Operation
  prop  :user,   _Ref(User)
  prop? :avatar, _Ref(Avatar)                    # optional (nilable)
  prop  :account, _Ref(Account, lock: true)       # row lock on fetch

  success _Ref(User)  # When recording: stores user.id instead of full object

  def perform
    # user is a User instance (coerced from ID if passed as ID)
    EmailService.send(user.email)
    user  # Return value; recording will store user.id
  end
end

# All of these work:
SendEmail.new(user: User.find(1)).call   # Instance
SendEmail.new(user: 1).call              # Integer ID
SendEmail.new(user: "1").call            # String ID
SendEmail.new(user: user_instance, avatar: nil).call  # Optional
```

**Outside the class body** (e.g., in tests), use `Dex::RefType.new(Model)` directly:
```ruby
assert_success_type(Dex::RefType.new(User))
```

**Lock option:** Use `lock: true` to acquire a row lock (`SELECT ... FOR UPDATE`) when coercing from ID. Useful inside transactions to prevent concurrent modifications.

```ruby
prop :user, _Ref(User, lock: true)
```

When an ID is passed, uses `Model.lock.find(id)`. When an instance is passed directly, no re-locking occurs.

**Coercion behavior:**
- Instance of model class → passes through (no lock, even with `lock: true`)
- `nil` → passes through (use `prop?` to allow nil)
- Integer or String → calls `Model.find(id)` (or `Model.lock.find(id)` with `lock: true`)
- Not found → raises `ActiveRecord::RecordNotFound`

**Serialization:** In `_props_as_json` (used by recording), Ref types serialize as the model's ID, not the full object.

```ruby
# _props_as_json => {"user" => 123}  (not full User object)
```

**Key facts:**
- `_Ref(Model)` is a class method available inside operation class body
- Outside class body, use `Dex::RefType.new(Model)` or `Dex::RefType.new(Model, lock: true)`
- Use `prop?` for optional refs (nilable with nil default)
- With `success _Ref(Model)`, recording stores the model ID (not full object)
- All model methods work directly on coerced value

---

## Class-Level DSL Reference

| Method | Purpose | Example |
|--------|---------|---------|
| `.call(**kwargs)` | Create instance and call synchronously (shorthand for `new(**kwargs).call`) | `MyOp.call(name: "Alice")` |
| `prop(name, type, **opts)` | Define required typed property | `prop :name, String` |
| `prop?(name, type, **opts)` | Define optional typed property (nilable, defaults to nil) | `prop? :note, String` |
| `success(type)` | Declare success return type (documentation + recording serialization) | `success _Ref(User)` |
| `error(*codes)` | Declare valid error codes; undeclared codes raise ArgumentError in `error!` | `error :not_found, :invalid` |
| `before(sym_or_proc = nil, &block)` | Register before callback | `before :validate` / `before { error!(:x) }` |
| `after(sym_or_proc = nil, &block)` | Register after callback | `after :notify` / `after -> { log }` |
| `around(sym_or_proc = nil, &block)` | Register around callback | `around :with_timing` / `around { \|c\| c.call }` |
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
| `call` | Result | Public entry point — invokes `perform` through the pipeline |
| `perform` | Result | Implement this — private, called by `call` |
| `error!(code, msg, details:)` | (halts) | Halt with failure — rolls back transaction, raises Dex::Error to caller |
| `success!(value, **attrs)` | (halts) | Halt with success — commits transaction, returns value |
| `assert!(code, &block)` / `assert!(value, code)` | value or (halts) | Guard against nil/false — returns value if truthy, calls `error!(code)` otherwise |
| `safe` | SafeProxy | Returns proxy for Ok/Err execution via `.safe.call` |
| `async(**opts)` | AsyncProxy | Returns proxy for background execution via `.async.call` |

---

## Key Behaviors (Non-Obvious)

1. **Props are reader methods** — All properties are accessible directly (e.g., `name` instead of needing a `params` accessor). No delegation layer; the property IS the method.

2. **Safe only catches `Dex::Error`** — Other exceptions (RuntimeError, ActiveRecord errors) propagate through `.safe.call` without wrapping.

3. **`success` validates at runtime; `error` guards typos** — `success(type)` documents the return type, validates the actual return value (raises `ArgumentError` on mismatch, nil is allowed), and affects recording serialization. `error(*codes)` documents valid error codes and guards against typos in `error!` calls.

4. **Ok delegates to value** — `ok.user_id` works if `ok.value` responds to `user_id`. No need to unwrap explicitly.

5. **Callbacks run inside transaction** — Errors in callbacks trigger rollback.

6. **Recording happens inside transaction** — When both are enabled, the operation record is rolled back if `perform` raises.

7. **`error!` skips recording; `success!` records normally** — `error!` halts before recording save (transaction rolls back). `success!` records the result just like a normal return. `success!` also runs `after` callbacks and `around` post-yield code; `error!` skips both.

8. **Nested operations share transaction** — If outer operation calls inner operation, both share the transaction. Outer rollback rolls back inner changes.

9. **Missing record columns OK** — Recording filters to only existing columns. A minimal table with just `name` and timestamps works.

10. **Async serializes and coerces props** — Props are serialized via `as_json` and transparently coerced back (Date, Time, BigDecimal, Symbol, Ref). Non-serializable props raise `ArgumentError` at enqueue time.

11. **Anonymous classes cannot record** — Operation class must have a name for recording to work.

12. **Settings inherit and merge** — Child classes inherit parent settings. Multiple `set` calls for same key merge (not replace).

13. **`rescue_from` converts to `Dex::Error`** — Mapped exceptions become structured errors, so `.safe`, pattern matching, transactions, and recording all behave consistently with `error!`.

14. **`rescue_from` inheritance** — Child classes inherit parent rescue handlers. Later declarations (child's own) take precedence for the same exception class.

15. **Advisory lock wraps outside transaction** — `advisory_lock` acquires the lock before the transaction starts. On timeout, raises `Dex::Error(:lock_timeout)`. Requires `with_advisory_lock` gem (optional, not in gemspec).

16. **Async + recording auto-optimizes** — When recording is enabled with params, `.async.call` stores only the record ID in Redis (via `RecordJob`) instead of the full params hash. This is automatic — no DSL changes needed. The record tracks `status` (`pending` → `running` → `done`/`failed`) and `error` (code or exception class name).

17. **Multi-level inheritance is safe** — Wrapper modules are registered as named pipeline steps via `use` on `Dex::Operation`. `Operation#call` invokes the pipeline, which executes steps in declared order. Child classes get independent pipeline copies. Side effects (recording, transaction wrapping, callbacks) execute exactly once regardless of inheritance depth.

18. **DSL arguments validated at declaration time** — All DSL methods (`error`, `rescue_from`, `async`, `record`, `advisory_lock`, `before`/`after`/`around`, `transaction`) validate their arguments when the class body is evaluated. Typos and wrong types raise `ArgumentError` immediately — your Ruby file won't finish loading with bad arguments. The low-level `set` method stays unvalidated (extensible foundation). Examples: `error "string"` raises (must be Symbol), `async priority: 5` raises (unknown option), `transaction :redis` raises (unknown adapter), `before 123` raises (must be Symbol or callable).

---

## Pipeline Architecture

`Operation#call` invokes an explicit pipeline of named steps. Each step's `_xxx_wrap` method receives a block (continuation) and calls `yield` to proceed to the next step, ending at `perform`.

**Default pipeline (execution order):**

| Step | Module | Wrap Method |
|------|--------|------------|
| `:result` | ResultWrapper | `_result_wrap` |
| `:lock` | LockWrapper | `_lock_wrap` |
| `:transaction` | TransactionWrapper | `_transaction_wrap` |
| `:record` | RecordWrapper | `_record_wrap` |
| `:rescue` | RescueWrapper | `_rescue_wrap` |
| `:callback` | CallbackWrapper | `_callback_wrap` |

### `use` DSL — Adding Custom Steps

Add custom wrapper modules to the pipeline in subclasses:

```ruby
module AuthorizationWrapper
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def authorize(policy)
      set(:authorize, policy: policy)
    end
  end

  def _authorization_wrap
    policy = self.class.settings_for(:authorize)[:policy]
    raise Dex::Error.new(:unauthorized) if policy && !policy.call(self)
    yield
  end
end

class SecureOp < Dex::Operation
  use AuthorizationWrapper, before: :callback
  authorize -> (op) { op.current_user.admin? }

  def perform
    # runs only if authorized
  end
end
```

**Positioning options:**
```ruby
use MyWrapper, as: :custom                  # append (innermost), step name :custom
use MyWrapper, as: :custom, before: :callback  # insert before :callback step
use MyWrapper, as: :custom, after: :rescue     # insert after :rescue step
use MyWrapper, as: :custom, at: :outer         # outermost position
use MyWrapper, as: :custom, at: :inner         # innermost position
use MyWrapper, as: :custom, wrap: :_my_method  # custom wrap method name
```

**Step name derivation:** For named modules, the step name is derived automatically by stripping `Wrapper` suffix and converting to snake_case (e.g., `AuthorizationWrapper` → `:authorization`). Anonymous modules require explicit `as:`.

**Pipeline inspection:**
```ruby
MyOp.pipeline.steps       # => [Step(:result, ...), Step(:lock, ...), ...]
MyOp.pipeline.steps.map(&:name)  # => [:result, :lock, :transaction, :record, :rescue, :callback]
```

**Inheritance:** Child classes get independent pipeline copies. Adding steps to a child does not affect the parent.

---

## Global Configuration

```ruby
# config/initializers/dexkit.rb
Dex.configure do |config|
  config.record_class = OperationRecord        # Model for recording (default: nil)
  config.transaction_adapter = nil               # auto-detect (default); or :active_record / :mongoid
end
```

---

## Full Example

```ruby
class CreateOrder < Dex::Operation
  async queue: "orders"
  transaction true  # Explicit (default anyway)

  prop :user,  _Ref(User)
  prop :items, _Array(Hash)
  prop :total, BigDecimal

  error :insufficient_stock

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

**Testing:** See `guides/llm/TESTING.md` for comprehensive test helpers (`Dex::TestHelpers`) — assertions, stubbing, spying, and the `Dex::TestLog` activity log.

**End of reference.** For the latest features, check the dexkit repository or CHANGELOG.
