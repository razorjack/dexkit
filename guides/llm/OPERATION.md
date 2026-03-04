# Dex::Operation — LLM Reference

Copy this to your app's operations directory (e.g., `app/operations/AGENTS.md`) so coding agents know the full API when implementing and testing operations.

---

## Reference Operation

All examples below build on this operation unless noted otherwise:

```ruby
class CreateUser < Dex::Operation
  prop :email, String
  prop :name,  String
  prop? :role, _Union("admin", "member"), default: "member"

  success _Ref(User)
  error :email_taken, :invalid_email

  def perform
    error!(:invalid_email) unless email.include?("@")
    error!(:email_taken) if User.exists?(email: email)

    user = User.create!(email: email, name: name, role: role)

    after_commit { WelcomeMailer.with(user: user).deliver_later }

    user
  end
end
```

**Calling:**

```ruby
CreateUser.call(email: "a@b.com", name: "Alice")            # shorthand for new(...).call
CreateUser.new(email: "a@b.com", name: "Alice").safe.call    # Ok/Err wrapper
CreateUser.new(email: "a@b.com", name: "Alice").async.call   # background job
```

Use `new(...)` form when chaining modifiers (`.safe`, `.async`).

---

## Properties

Define typed inputs with `prop` (required) and `prop?` (optional — nilable, defaults to `nil`). Access directly as reader methods (`name`, `user`). Invalid values raise `Literal::TypeError`.

Reserved names: `call`, `perform`, `async`, `safe`, `initialize`.

### Literal Types Cheatsheet

Types use `===` for validation. All constructors available in the operation class body:

| Constructor | Description | Example |
|-------------|-------------|---------|
| Plain class | Matches with `===` | `String`, `Integer`, `Float`, `Hash`, `Array` |
| `_Integer(range)` | Constrained integer | `_Integer(1..)`, `_Integer(0..100)` |
| `_String(constraints)` | Constrained string | `_String(length: 1..500)` |
| `_Array(type)` | Typed array | `_Array(Integer)`, `_Array(String)` |
| `_Union(*values)` | Enum of values | `_Union("USD", "EUR", "GBP")` |
| `_Nilable(type)` | Nilable wrapper | `_Nilable(String)` |
| `_Ref(Model)` | Model reference | `_Ref(User)`, `_Ref(Account, lock: true)` |

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

### _Ref(Model)

Accepts model instances or IDs, coerces IDs via `Model.find(id)`. With `lock: true`, uses `Model.lock.find(id)` (SELECT FOR UPDATE). Instances pass through without re-locking. In serialization (recording, async), stores model ID only.

Outside the class body (e.g., in tests), use `Dex::RefType.new(Model)` instead of `_Ref(Model)`.

---

## Contract

Optional declarations documenting intent and catching mistakes at runtime.

**`success(type)`** — validates return value (`nil` always allowed; raises `ArgumentError` on mismatch):

```ruby
success _Ref(User)   # perform must return a User (or nil)
```

**`error(*codes)`** — restricts which codes `error!`/`assert!` accept (raises `ArgumentError` on undeclared):

```ruby
error :email_taken, :invalid_email
```

Both inherit from parent class. Without `error` declaration, any code is accepted.

**Introspection:** `MyOp.contract` returns a frozen `Data` with `params`, `success`, `errors` fields. Supports pattern matching and `to_h`.

---

## Flow Control

All three halt execution immediately via non-local exit (work from `perform`, helpers, and callbacks).

**`error!(code, message = nil, details: nil)`** — halt with failure, roll back transaction, raise `Dex::Error`:

```ruby
error!(:not_found, "User not found")
error!(:validation_failed, details: { field: "email" })
```

**`success!(value = nil, **attrs)`** — halt with success, commit transaction:

```ruby
success!(user)                      # return value early
success!(name: "John", age: 30)    # kwargs become Hash
```

**`assert!(code, &block)` / `assert!(value, code)`** — returns value if truthy, otherwise `error!(code)`:

```ruby
user = assert!(:not_found) { User.find_by(id: id) }
assert!(user.active?, :inactive)
```

**Dex::Error** has `code` (Symbol), `message` (String, defaults to code.to_s), `details` (any). Pattern matching:

```ruby
begin
  CreateUser.call(email: "bad", name: "A")
rescue Dex::Error => e
  case e
  in {code: :not_found} then handle_not_found
  in {code: :validation_failed, details: {field:}} then handle_field(field)
  end
end
```

**Key differences:** `error!`/`assert!` roll back transaction, skip `after` callbacks and recording. `success!` commits, runs `after` callbacks, records normally.

---

## Safe Execution (Ok/Err)

`.safe.call` wraps results instead of raising. Only catches `Dex::Error` — other exceptions propagate normally.

```ruby
result = CreateUser.new(email: "a@b.com", name: "Alice").safe.call

# Ok
result.ok?     # => true
result.value   # => User instance (also: result.name delegates to value)

# Err
result.error?  # => true
result.code    # => :email_taken
result.message # => "email_taken"
result.details # => nil or Hash
result.value!  # re-raises Dex::Error
```

**Pattern matching:**

```ruby
case CreateUser.new(email: "a@b.com", name: "Alice").safe.call
in Dex::Ok(name:)               then puts "Created #{name}"
in Dex::Err(code: :email_taken) then puts "Already exists"
end
```

`Ok`/`Err` are available inside operations without prefix. In other contexts (controllers, POROs), use `Dex::Ok`/`Dex::Err` or `include Dex::Match`.

---

## Rescue Mapping

Map exceptions to structured `Dex::Error` codes — eliminates begin/rescue boilerplate:

```ruby
class ChargeCard < Dex::Operation
  rescue_from Stripe::CardError,                  as: :card_declined
  rescue_from Stripe::RateLimitError,             as: :rate_limited
  rescue_from Net::OpenTimeout, Net::ReadTimeout, as: :timeout
  rescue_from Stripe::APIError,                   as: :provider_error, message: "Stripe is down"

  def perform
    Stripe::Charge.create(amount: amount, source: token)
  end
end
```

- `as:` (required): error code Symbol. `message:` (optional): overrides exception message
- Original exception preserved in `err.details[:original]`
- Subclass exceptions match parent handlers; child handlers take precedence
- Converted errors trigger transaction rollback and work with `.safe` (consistent with `error!`)

---

## Callbacks

```ruby
class ProcessOrder < Dex::Operation
  before :validate_stock            # symbol → instance method
  before -> { log("starting") }     # lambda (instance_exec'd)
  after  :send_confirmation         # runs after successful perform
  around :with_timing               # wraps everything, must yield

  def validate_stock
    error!(:out_of_stock) unless in_stock?
  end

  def with_timing
    start = Time.now
    yield
    puts Time.now - start
  end
end
```

- **Order:** `around` wraps → `before` → `perform` → `after`
- `around` with proc/lambda: receives continuation arg, call `cont.call`
- `before` calling `error!` stops everything; `after` skipped on error
- Callbacks run **inside** the transaction — errors trigger rollback
- Inheritance: parent callbacks run first, then child

---

## Transactions

Operations run inside database transactions by default. All changes roll back on error. Nested operations share the outer transaction.

```ruby
transaction false        # disable
transaction :mongoid     # adapter override (default: auto-detect AR → Mongoid)
```

Child classes can re-enable: `transaction true`.

### after_commit

Register blocks to run after the transaction commits. Use for side effects that should only happen on success (emails, webhooks, cache invalidation):

```ruby
def perform
  user = User.create!(name: name, email: email)
  after_commit { WelcomeMailer.with(user: user).deliver_later }
  after_commit { Analytics.track(:user_created, user_id: user.id) }
  user
end
```

On rollback (`error!` or exception), callbacks are discarded. When no transaction is open anywhere, executes immediately. Multiple blocks run in registration order.

**ActiveRecord:** fully nesting-aware — callbacks are deferred until the outermost transaction commits, even across nested operations or ambient `ActiveRecord::Base.transaction` blocks. Requires Rails 7.2+.

**Mongoid:** callbacks are deferred across nested Dex operations. Ambient `Mongoid.transaction` blocks opened outside Dex are not detected — callbacks will fire immediately in that case.

---

## Advisory Locking

Mutual exclusion via database advisory locks (requires `with_advisory_lock` gem). Wraps **outside** the transaction.

```ruby
advisory_lock { "pay:#{charge_id}" }    # dynamic key from props
advisory_lock "daily-report"            # static key
advisory_lock "report", timeout: 5      # with timeout (seconds)
advisory_lock                           # class name as key
advisory_lock :compute_key              # instance method
```

On timeout: raises `Dex::Error(code: :lock_timeout)`. Works with `.safe`.

---

## Async Execution

Enqueue as background jobs (requires ActiveJob):

```ruby
CreateUser.new(email: "a@b.com", name: "Alice").async.call
CreateUser.new(email: "a@b.com", name: "Alice").async(queue: "urgent").call
CreateUser.new(email: "a@b.com", name: "Alice").async(in: 5.minutes).call
CreateUser.new(email: "a@b.com", name: "Alice").async(at: 1.hour.from_now).call
```

Class-level defaults: `async queue: "mailers"`. Runtime options override.

Props serialize/deserialize automatically (Date, Time, BigDecimal, Symbol, `_Ref` — all handled). Non-serializable props raise `ArgumentError` at enqueue time.

---

## Recording

Record execution to database. Requires `Dex.configure { |c| c.record_class = OperationRecord }`.

```ruby
create_table :operation_records do |t|
  t.string   :name           # Required: operation class name
  t.jsonb    :params         # Optional: serialized props
  t.jsonb    :response       # Optional: serialized result
  t.string   :status         # Optional: pending/running/done/failed (for async)
  t.string   :error          # Optional: error code on failure
  t.datetime :performed_at   # Optional
  t.timestamps
end
```

Control per-operation:

```ruby
record false              # disable entirely
record response: false    # params only
record params: false      # response only
```

Recording happens inside the transaction — rolled back on `error!`/`assert!`. Missing columns silently skipped.

When both async and recording are enabled, Dexkit automatically stores only the record ID in the job payload instead of full params. The record tracks `status` (pending → running → done/failed) and `error` (code or exception class name).

---

## Configuration

```ruby
# config/initializers/dexkit.rb
Dex.configure do |config|
  config.record_class = OperationRecord  # model for recording (default: nil)
  config.transaction_adapter = nil        # auto-detect (default); or :active_record / :mongoid
end
```

All DSL methods validate arguments at declaration time — typos and wrong types raise `ArgumentError` immediately (e.g., `error "string"`, `async priority: 5`, `transaction :redis`).

---

## Testing

```ruby
# test/test_helper.rb
require "dex/test_helpers"

class Minitest::Test
  include Dex::TestHelpers
end
```

Not autoloaded — stays out of production. TestLog and stubs are auto-cleared in `setup`.

For Mongoid-backed operation tests, run against a MongoDB replica set (MongoDB transactions require it).

### Subject & Execution

```ruby
class CreateUserTest < Minitest::Test
  include Dex::TestHelpers

  testing CreateUser  # default for all helpers

  def test_example
    result = call_operation(email: "a@b.com", name: "Alice")   # => Ok or Err (safe)
    value  = call_operation!(email: "a@b.com", name: "Alice")  # => raw value or raises
  end
end
```

All helpers accept an explicit class as first arg: `call_operation(OtherOp, name: "x")`.

### Result Assertions

```ruby
assert_ok result                        # passes if Ok
assert_ok result, user                  # checks value equality
assert_ok(result) { |val| assert val }  # yields value

assert_err result                       # passes if Err
assert_err result, :not_found           # checks code
assert_err result, :fail, message: "x"  # checks message (String or Regex)
assert_err result, :fail, details: { field: "email" }
assert_err(result, :fail) { |err| assert err } # yields Dex::Error

refute_ok result
refute_err result
refute_err result, :not_found           # Ok OR different code
```

### One-Liner Assertions

Call + assert in one step:

```ruby
assert_operation(email: "a@b.com", name: "Alice")                # Ok
assert_operation(CreateUser, email: "a@b.com", name: "Alice")    # explicit class
assert_operation(email: "a@b.com", name: "Alice", returns: user) # check value

assert_operation_error(:invalid_email, email: "bad", name: "A")
assert_operation_error(CreateUser, :email_taken, email: "taken@b.com", name: "A")
```

### Contract Assertions

```ruby
assert_params(:name, :email, :role)                  # exhaustive names (order-independent)
assert_params(name: String, email: String)            # with types
assert_accepts_param(:name)                           # subset check

assert_success_type(Dex::RefType.new(User))           # use Dex::RefType outside class body
assert_error_codes(:email_taken, :invalid_email)

assert_contract(
  params: [:name, :email, :role],
  success: Dex::RefType.new(User),
  errors: [:email_taken, :invalid_email]
)
```

### Param Validation

```ruby
assert_invalid_params(name: 123)                      # asserts Literal::TypeError
assert_valid_params(email: "a@b.com", name: "Alice")  # no error (doesn't call perform)
```

### Async & Transaction Assertions

Async requires `ActiveJob::TestHelper`:

```ruby
assert_enqueues_operation(email: "a@b.com", name: "Alice")
assert_enqueues_operation(CreateUser, email: "a@b.com", name: "Alice", queue: "default")
refute_enqueues_operation { do_something }
```

Transaction:

```ruby
assert_rolls_back(User) { CreateUser.call(email: "bad", name: "A") }
assert_commits(User) { CreateUser.call(email: "ok@b.com", name: "A") }
```

### Batch Assertions

```ruby
assert_all_succeed(params_list: [
  { email: "a@b.com", name: "A" },
  { email: "b@b.com", name: "B" }
])

assert_all_fail(code: :invalid_email, params_list: [
  { email: "", name: "A" },
  { email: "no-at", name: "B" }
])
# Also supports message: and details: options
```

### Stubbing

Replace an operation within a block. Bypasses all wrappers, not recorded in TestLog:

```ruby
stub_operation(SendWelcomeEmail, returns: "fake") do
  call_operation!(email: "a@b.com", name: "Alice")
end

stub_operation(SendWelcomeEmail, error: :not_found) do
  # raises Dex::Error(code: :not_found)
end

stub_operation(SendWelcomeEmail, error: { code: :fail, message: "oops" }) do
  # raises Dex::Error with code and message
end
```

### Spying

Observe real execution without modifying behavior:

```ruby
spy_on_operation(SendWelcomeEmail) do |spy|
  CreateUser.call(email: "a@b.com", name: "Alice")

  spy.called?                          # => true
  spy.called_once?                     # => true
  spy.call_count                       # => 1
  spy.last_result                      # => Ok or Err
  spy.called_with?(email: "a@b.com")   # => true (subset match)
end
```

### TestLog

Global log of all operation calls:

```ruby
Dex::TestLog.calls                               # all entries
Dex::TestLog.find(CreateUser)                    # filter by class
Dex::TestLog.find(CreateUser, email: "a@b.com")  # filter by class + params
Dex::TestLog.size; Dex::TestLog.empty?; Dex::TestLog.clear!
Dex::TestLog.summary                             # human-readable for failure messages
```

Each entry has: `name`, `operation_class`, `params`, `result` (Ok/Err), `duration`, `caller_location`.

### Complete Test Example

```ruby
class CreateUserTest < Minitest::Test
  include Dex::TestHelpers

  testing CreateUser

  def test_contract
    assert_params(:name, :email, :role)
    assert_success_type(Dex::RefType.new(User))
    assert_error_codes(:email_taken, :invalid_email)
  end

  def test_creates_user
    result = call_operation(email: "a@b.com", name: "Alice")
    assert_ok(result) { |user| assert_equal "Alice", user.name }
  end

  def test_one_liner
    assert_operation(email: "a@b.com", name: "Alice")
  end

  def test_rejects_bad_email
    assert_operation_error(:invalid_email, email: "bad", name: "A")
  end

  def test_batch_rejects
    assert_all_fail(code: :invalid_email, params_list: [
      { email: "", name: "A" },
      { email: "no-at", name: "B" }
    ])
  end

  def test_stubs_dependency
    stub_operation(SendWelcomeEmail, returns: true) do
      call_operation!(email: "a@b.com", name: "Alice")
    end
  end

  def test_spies_on_dependency
    spy_on_operation(SendWelcomeEmail) do |spy|
      call_operation!(email: "a@b.com", name: "Alice")
      assert spy.called_once?
    end
  end
end
```

---

**End of reference.**
