# Dex::Operation — LLM Reference

Install with `rake dex:guides` or copy manually to `app/operations/AGENTS.md`.

---

## Reference Operation

All examples below build on this operation unless noted otherwise:

```ruby
class CreateUser < Dex::Operation
  prop :email, String
  prop :name, String
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
CreateUser.new(email: "a@b.com", name: "Alice").once("key").call  # call-site idempotency
```

Use `new(...)` form when chaining modifiers (`.safe`, `.async`, `.once`).

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
prop :name, String                       # any String
prop :count, Integer                      # any Integer
prop :amount, Float                        # any Float
prop :amount, BigDecimal                   # any BigDecimal
prop :data, Hash                         # any Hash
prop :items, Array                        # any Array
prop :active, _Boolean                     # true or false
prop :role, Symbol                       # any Symbol
prop :count, _Integer(1..)                # Integer >= 1
prop :count, _Integer(0..100)             # Integer 0–100
prop :name, _String(length: 1..255)      # String with length constraint
prop :score, _Float(0.0..1.0)             # Float in range
prop :tags, _Array(String)               # Array of Strings
prop :ids, _Array(Integer)              # Array of Integers
prop :matrix, _Array(_Array(Integer))      # nested typed arrays
prop :currency, _Union("USD", "EUR", "GBP")  # enum of values
prop :id, _Union(String, Integer)      # union of types
prop :label, _Nilable(String)             # String or nil
prop :meta, _Hash(Symbol, String)        # Hash with typed keys+values
prop :pair, _Tuple(String, Integer)      # fixed-size typed array
prop :name, _Frozen(String)              # must be frozen
prop :handler, _Callable                    # anything responding to .call
prop :handler, _Interface(:call, :arity)    # responds to listed methods
prop :user, _Ref(User)                   # Dex-specific: model by instance or ID
prop :account, _Ref(Account, lock: true)    # Dex-specific: with row lock
prop :title, String, default: "Untitled"  # default value
prop? :note, String                       # optional (nilable, default: nil)
```

### _Ref(Model)

Accepts model instances or IDs, coerces IDs via `Model.find(id)`. With `lock: true`, uses `Model.lock.find(id)` (SELECT FOR UPDATE) – requires a model that responds to `.lock` (ActiveRecord). Mongoid documents do not support row locks and raise `ArgumentError` at declaration time. Instances pass through without re-locking. In serialization (recording, async), stores model ID only via `id.as_json`, so Mongoid BSON::ObjectId values are safe in ActiveJob payloads too. IDs are treated as strings in JSON Schema – this supports integer PKs, UUIDs, and Mongoid BSON::ObjectId equally.

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

**Introspection:** `MyOp.contract` returns a frozen `Data` with `params`, `success`, `errors`, `guards` fields. Supports pattern matching and `to_h`.

---

## Ambient Context

Map props to ambient context keys so they auto-fill from `Dex.with_context` when not passed explicitly. Explicit kwargs always win.

```ruby
class Order::Place < Dex::Operation
  prop :product, _Ref(Product)
  prop :customer, _Ref(Customer)
  prop :locale, Symbol

  context customer: :current_customer   # prop :customer ← Dex.context[:current_customer]
  context :locale                       # shorthand: prop :locale ← Dex.context[:locale]
end
```

**Setting context** (controller, middleware):

```ruby
Dex.with_context(current_customer: customer, locale: I18n.locale) do
  Order::Place.call(product: product)   # customer + locale auto-filled
end
```

**Resolution order:** explicit kwarg → ambient context → prop default → TypeError (if required).

**In tests** — just pass everything explicitly. No `Dex.with_context` needed:

```ruby
Order::Place.call(product: product, customer: customer, locale: :en)
```

**Nesting** supported — inner blocks merge with outer, restore on exit. Nested operations inherit the same ambient context.

**Works with guards** — context-mapped props are available in guard blocks and `callable?`:

```ruby
Dex.with_context(current_customer: customer) do
  Order::Place.callable?(product: product)
end
```

**Works with optional props** (`prop?`) — if ambient context has the key, it fills in. If not, the prop is nil.

**Introspection:** `MyOp.context_mappings` returns `{ customer: :current_customer, locale: :locale }`.

**DSL validation:** `context user: :current_user` raises `ArgumentError` if no `prop :user` has been declared. Context declarations must come after the props they reference.

---

## Guards

Inline precondition checks. The guard name is the error code, the block detects the **threat** (truthy = threat detected = operation fails):

```ruby
class PublishPost < Dex::Operation
  prop :post, _Ref(Post)
  prop :user, _Ref(User)

  guard :unauthorized, "Only the author or admins can publish" do
    !user.admin? && post.author != user
  end

  guard :already_published, "Post must be in draft state" do
    post.published?
  end

  def perform
    post.update!(published_at: Time.current)
    post
  end
end
```

- Guards run in declaration order, before `perform`, after `rescue`
- All independent guards run – failures are collected, not short-circuited
- Guard names are auto-declared as error codes (no separate `error :unauthorized` needed)
- Same error code usable with `error!` in `perform`

**Dependencies:** skip dependent guards when a dependency fails:

```ruby
guard :missing_author, "Author must be present" do
  author.blank?
end

guard :unpaid_author, "Author must be a paid subscriber", requires: :missing_author do
  author.free_plan?
end
```

If author is nil: only `:missing_author` is reported. `:unpaid_author` is skipped.

**Introspection** – check guards without running `perform`:

```ruby
PublishPost.callable?(post: post, user: user)           # => true/false
PublishPost.callable?(:unauthorized, post: post, user: user) # check specific guard
result = PublishPost.callable(post: post, user: user)   # => Ok or Err with details
result.details  # => [{ guard: :unauthorized, message: "..." }, ...]
```

`callable` bypasses the pipeline – no locks, transactions, recording, or callbacks. Cheap and side-effect-free.

**Contract:** `contract.guards` returns guard metadata. `contract.errors` includes guard codes.

**Inheritance:** parent guards run first, child guards appended.

**DSL validation:** code must be Symbol, block required, `requires:` must reference previously declared guards, duplicates raise `ArgumentError`.

---

## Explain

Full preflight check — resolves context, coerces props, evaluates guards, computes derived keys, reports settings. No side effects, `perform` never runs.

```ruby
info = Order::Place.explain(product: product, customer: customer, quantity: 2)
```

Returns a frozen Hash:

```ruby
info = Order::Place.explain(product: product, customer: customer, quantity: 2)
# => {
#   operation: "Order::Place",
#   props: { product: #<Product>, customer: #<Customer>, quantity: 2 },
#   context: {
#     resolved: { customer: #<Customer> },
#     mappings: { customer: :current_customer },
#     source: { customer: :ambient }   # :ambient, :explicit, or :default
#   },
#   guards: {
#     passed: true,
#     results: [{ name: :out_of_stock, passed: true }, ...]
#   },
#   once: { active: true, key: "Order::Place/product_id=7", status: :fresh, expires_in: nil },
#   lock: { active: true, key: "order:7", timeout: nil },
#   record: { enabled: true, params: true, result: true },
#   transaction: { enabled: true },
#   rescue_from: { "Stripe::CardError" => :card_declined },
#   callbacks: { before: 1, after: 2, around: 0 },
#   pipeline: [:trace, :result, :guard, :once, :lock, :record, :transaction, :rescue, :callback],
#   callable: true
# }
```

- Invalid props (`Literal::TypeError`, `ArgumentError`) return a partial result with `info[:error]` — class-level info still available, instance-dependent sections degrade to empty/nil. Static lock keys preserved. Context source uses `:missing` for props without defaults. Other errors propagate normally
- `info[:callable]` is a full preflight verdict — checks guards AND once blocking statuses; always `false` when props are invalid
- Once status: `:fresh` (new), `:exists` (would replay), `:expired`, `:pending` (in-flight), `:invalid` (nil key), `:misconfigured` (anonymous op, missing record step, missing column), `:unavailable` (no backend)
- Guard results include `message:` on failures and `skipped: true` when a guard was skipped via `requires:` dependency
- Custom middleware can contribute via `_name_explain(instance, info)` class methods

**Use cases:** console debugging, admin tooling, LLM agent preflight, test assertions.

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
  in { code: :not_found } then handle_not_found
  in { code: :validation_failed, details: { field: } } then handle_field(field)
  end
end
```

**Key differences:** `error!`/`assert!` roll back transaction, skip `after` callbacks, but are still recorded (status `error`). `success!` commits, runs `after` callbacks, records normally (status `completed`).

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
in Dex::Ok(name:) then puts "Created #{name}"
in Dex::Err(code: :email_taken) then puts "Already exists"
end
```

`Ok`/`Err` are available inside operations without prefix. In other contexts (controllers, POROs), use `Dex::Ok`/`Dex::Err` or `include Dex::Match`.

---

## Rescue Mapping

Map exceptions to structured `Dex::Error` codes — eliminates begin/rescue boilerplate:

```ruby
class ChargeCard < Dex::Operation
  rescue_from Stripe::CardError, as: :card_declined
  rescue_from Stripe::RateLimitError, as: :rate_limited
  rescue_from Net::OpenTimeout, Net::ReadTimeout, as: :timeout
  rescue_from Stripe::APIError, as: :provider_error, message: "Stripe is down"

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
  after :send_confirmation         # runs after successful perform
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

Operations run inside database transactions when Dex has an active transaction adapter. ActiveRecord is auto-detected. In Mongoid-only apps, no adapter is active, so transactions are automatically disabled – but `after_commit` still works (callbacks fire immediately after success). If you need Mongoid transactions, use `Mongoid.transaction` directly inside `perform`.

```ruby
transaction false        # disable
transaction :active_record  # explicit adapter
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

Callbacks are always deferred — they run after the outermost operation boundary succeeds:

- **Transactional operations:** deferred until the DB transaction commits.
- **Non-transactional operations (including Mongoid-only):** queued in memory, flushed after the operation pipeline completes successfully.
- **Nested operations:** callbacks queue up and flush once at the outermost successful boundary.
- **On error (`error!` or exception):** queued callbacks are discarded.

Multiple blocks run in registration order.

**ActiveRecord:** requires Rails 7.2+ (`after_all_transactions_commit`).

---

## Advisory Locking

Mutual exclusion via database advisory locks (requires `with_advisory_lock` gem). Wraps **outside** the transaction. ActiveRecord-only; Mongoid-only apps get a clear `LoadError`.

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
create_table :operation_records, id: :string do |t|
  t.string :name, null: false  # operation class name
  t.string :trace_id           # shared trace / correlation ID
  t.string :actor_type         # root actor type
  t.string :actor_id           # root actor ID
  t.jsonb :trace               # full trace snapshot
  t.jsonb :params              # serialized props (nil = not captured)
  t.jsonb :result              # serialized return value
  t.string :status, null: false # pending/running/completed/error/failed
  t.string :error_code          # Dex::Error code or exception class
  t.string :error_message       # human-readable message
  t.jsonb :error_details       # structured details hash
  t.string :once_key            # idempotency key (used by `once`)
  t.datetime :once_key_expires_at # key expiry (used by `once`)
  t.datetime :performed_at        # execution completion timestamp
  t.timestamps
end

add_index :operation_records, :name
add_index :operation_records, :status
add_index :operation_records, [:name, :status]
add_index :operation_records, :trace_id
add_index :operation_records, [:actor_type, :actor_id]
```

Control per-operation:

```ruby
record false              # disable entirely
record result: false      # params only
record params: false      # result only
```

All outcomes are recorded — success (`completed`), business errors (`error`), and exceptions (`failed`). Recording runs outside the operation's own transaction so error records survive its rollbacks. Records still participate in ambient transactions (e.g., an outer operation's transaction). Dex validates the configured record model before use and raises if required attributes are missing.

Required attributes by feature:

- Core recording: `name`, `status`, `error_code`, `error_message`, `error_details`, `performed_at`
- Params capture: `params` unless `record params: false`
- Result capture: `result` unless `record result: false`
- Async record jobs: `params`
- `once`: `once_key`, plus `once_key_expires_at` when `expires_in:` is used

Trace columns (`id`, `trace_id`, `actor_type`, `actor_id`, `trace`) are recommended for tracing. Dex persists them when present, omits them when missing.

Untyped results are sanitized to JSON-safe values before persistence: Hash keys round-trip as strings, and objects fall back to `as_json`/`to_s` under `"_dex_value"`.

Status values: `pending` (async enqueued), `running` (async executing), `completed` (success), `error` (business error via `error!`), `failed` (unhandled exception).

When both async and recording are enabled, dexkit automatically stores only the record ID in the job payload instead of full params.

## Execution tracing

Every operation call gets an `op_...` execution ID and joins a fiber-local trace shared across operations, handlers, and async jobs.

```ruby
Dex::Trace.start(actor: { type: :user, id: current_user.id }) do
  Order::Place.call(product: product, customer: customer, quantity: 2)
end

Dex::Trace.trace_id   # => "tr_..."
Dex::Trace.current    # => [{ type: :actor, ... }, { type: :operation, ... }]
Dex::Trace.to_s       # => "user:42 > Order::Place(op_2nFg7K)"
```

Tracing is always on – no opt-in needed. Async operations serialize and restore the trace automatically. When recording is enabled, `trace_id`, `actor_type`, `actor_id`, and `trace` are persisted alongside the usual record fields.

---

## Idempotency (once)

Prevent duplicate execution with `once`. Requires recording to be configured (uses the record backend to store and look up idempotency keys).

**Class-level declaration:**

```ruby
class ChargeOrder < Dex::Operation
  prop :order_id, Integer
  once :order_id                              # key: "ChargeOrder/order_id=123"

  def perform
    Stripe::Charge.create(amount: order.total)
  end
end
```

Key forms:

```ruby
once :order_id                                # single prop → "ClassName/order_id=1"
once :merchant_id, :plan_id                   # composite  → "ClassName/merchant_id=1/plan_id=2" (sorted)
once                                          # bare — all props as key
once { "payment-#{order_id}" }                # block — custom key (no auto scoping)
once :user_id, expires_in: 24.hours           # key expires after duration
```

**Call-site key** — override or add idempotency at the call site:

```ruby
MyOp.new(payload: "data").once("webhook-123").call   # explicit key
MyOp.new(order_id: 1).once(nil).call                 # bypass once guard entirely
```

Works without a class-level `once` declaration — useful for one-off idempotency from controllers or jobs.

**Replay behavior:**

- Success results and business errors (`error!`) are replayed from the stored record. The operation does not re-execute.
- Unhandled exceptions release the key — the next call retries normally.
- Works with `.safe.call` (replays as `Ok`/`Err`) and `.async.call`.

**Clearing keys:**

```ruby
ChargeOrder.clear_once!(order_id: 1)      # by prop values (builds scoped key)
ChargeOrder.clear_once!("webhook-123")    # by raw string key
```

Clearing is idempotent — clearing a non-existent key is a no-op. After clearing, the next call executes normally.

**Pipeline position:** trace → result → guard → **once** → lock → record → transaction → rescue → callback. The once check runs before locking and recording, so duplicate calls short-circuit early.

**Requirements:**

- Record backend must be configured (`Dex.configure { |c| c.record_class = OperationRecord }`)
- The record backend must satisfy the Recording requirements above, and `once` additionally requires `once_key` plus `once_key_expires_at` when `expires_in:` is used
- `once` cannot be declared with `record false` — raises `ArgumentError`
- Only one `once` declaration per operation

---

## Configuration

```ruby
# config/initializers/dexkit.rb
Dex.configure do |config|
  config.record_class = OperationRecord  # model for recording (default: nil)
end
```

All DSL methods validate arguments at declaration time — typos and wrong types raise `ArgumentError` immediately (e.g., `error "string"`, `async priority: 5`, `transaction :redis`). Only `:active_record` is a valid transaction adapter.

---

## Testing

```ruby
# test/test_helper.rb
require "dex/operation/test_helpers"

class Minitest::Test
  include Dex::Operation::TestHelpers
end
```

Not autoloaded — stays out of production. TestLog and stubs are auto-cleared in `setup`.

### Subject & Execution

```ruby
class CreateUserTest < Minitest::Test
  include Dex::Operation::TestHelpers

  testing CreateUser  # default for all helpers

  def test_example
    result = call_operation(email: "a@b.com", name: "Alice")   # => Ok or Err (safe)
    value = call_operation!(email: "a@b.com", name: "Alice")  # => raw value or raises
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

### Guard Assertions

```ruby
assert_callable(post: post, user: user)                          # all guards pass
assert_callable(PublishPost, post: post, user: user)             # explicit class
refute_callable(:unauthorized, post: post, user: user)           # specific guard fails
refute_callable(PublishPost, :unauthorized, post: post, user: user)
```

Guard failures on the normal `call` path produce `Dex::Error`, so `assert_operation_error` and `assert_err` also work.

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
Dex::TestLog.size
Dex::TestLog.empty?
Dex::TestLog.clear!
Dex::TestLog.summary                             # human-readable for failure messages
```

Each entry has: `name`, `operation_class`, `params`, `result` (Ok/Err), `duration`, `caller_location`.

### Complete Test Example

```ruby
class CreateUserTest < Minitest::Test
  include Dex::Operation::TestHelpers

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

## Registry, Export & Description

### Description

Operations can declare a human-readable description. Props can include `desc:`:

```ruby
class Order::Place < Dex::Operation
  description "Places a new order, charges payment, and schedules fulfillment"

  prop :product, _Ref(Product), desc: "Product to order"
  prop :quantity, _Integer(1..), desc: "Number of units"
end
```

Descriptions appear in `contract.to_h`, `to_json_schema`, `explain`, and LLM tool definitions.

### Registry

```ruby
Dex::Operation.registry          # => #<Set: {Order::Place, Order::Cancel, ...}>
Dex::Operation.deregister(klass) # remove from registry (useful in tests)
Dex::Operation.clear!            # empty the registry
```

Only named, reachable classes are included. Anonymous classes and stale objects from code reloads are excluded. Populates lazily via `inherited` — in Rails, `eager_load!` to get the full list.

### Export

```ruby
Order::Place.contract.to_h
# => { name: "Order::Place", description: "...", params: { product: { type: "Ref(Product)", required: true, desc: "..." } }, ... }

Order::Place.contract.to_json_schema                    # params input schema (default)
Order::Place.contract.to_json_schema(section: :success) # success return schema
Order::Place.contract.to_json_schema(section: :errors)  # error catalog schema
Order::Place.contract.to_json_schema(section: :full)    # everything

Dex::Operation.export                          # all operations as hashes
Dex::Operation.export(format: :json_schema)    # all as JSON Schema
```

### LLM Tools (ruby-llm integration)

```ruby
chat = RubyLLM.chat
chat.with_tools(*Dex::Tool.all)                     # all operations as tools
chat.with_tools(*Dex::Tool.from_namespace("Order")) # namespace filter
chat.with_tools(Dex::Tool.explain_tool)              # preflight check tool

Dex.with_context(current_user: user) do
  chat.ask("Place an order for 2 units of product #42")
end
```

Requires `gem 'ruby_llm'` in your Gemfile. Lazy-loaded — ruby-llm is only required when you call `Dex::Tool`.

---

**End of reference.**
