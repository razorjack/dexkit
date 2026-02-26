# Dexkit

Rails patterns toolbelt. Equip to gain +10 DEX.

## Installation

```ruby
gem 'dexkit'
```

## Operations

Service objects with typed parameters.

```ruby
class SendWelcomeEmail < Dex::Operation
  params do
    attribute :user_id, Types::Integer
    attribute :template, Types::String.default("default")
  end

  def perform
    user = User.find(user_id)
    Mailer.welcome(user, template: template).deliver_later
  end
end

SendWelcomeEmail.new(user_id: 123).call
```

### Parameter Delegation

By default, all params are accessible directly in `perform` without the `params.` prefix:

```ruby
class CreateUser < Dex::Operation
  params do
    attribute :email, Types::String
    attribute :name, Types::String
  end

  def perform
    User.create!(email: email, name: name)  # direct access
    params.email  # params accessor still available too
  end
end
```

Control delegation with the `delegate:` option:

```ruby
params(delegate: false) { ... }              # no delegation
params(delegate: :email) { ... }             # delegate only :email
params(delegate: [:email, :name]) { ... }    # delegate specific list
```

### Async Execution

Requires ActiveJob. Enqueue operations as background jobs.

```ruby
# Enqueue immediately
SendWelcomeEmail.new(user_id: 123).async.call

# With options
SendWelcomeEmail.new(user_id: 123).async(queue: "low").call
SendWelcomeEmail.new(user_id: 123).async(in: 5.minutes).call
SendWelcomeEmail.new(user_id: 123).async(at: 1.hour.from_now).call

# Class-level defaults
class SendWelcomeEmail < Dex::Operation
  async queue: "mailers"
  # ...
end
```

Typed params (`Date`, `Time`, `BigDecimal`, `Symbol`, `Record`) automatically survive the JSON round-trip — no need to switch types. Direct calls remain strict. Non-serializable params raise `ArgumentError` at enqueue time.

### Result Objects

Define typed result structs for your operations.

```ruby
class CreateUser < Dex::Operation
  params do
    attribute :email, Types::String
    attribute :name, Types::String
  end

  result do
    attribute :user_id, Types::Integer
    attribute :status, Types::String
  end

  def perform
    user = User.create!(email: email, name: name)
    {user_id: user.id, status: "created"}
  end
end

result = CreateUser.new(email: "user@example.com", name: "John").call
result.user_id  # => 1
result.status   # => "created"
```

### Error Handling

Signal failures explicitly with `error!`. Automatically triggers transaction rollback.

```ruby
class ProcessPayment < Dex::Operation
  params do
    attribute :amount, Types::Integer
  end

  def perform
    if amount < 0
      error!(:invalid_amount, "Amount must be positive")
    end

    # Process payment...
  end
end

ProcessPayment.new(amount: -100).call
# raises Dex::Error with code: :invalid_amount
```

Add details to errors:

```ruby
error!(:validation_failed, "Invalid data", details: {field: "email", issue: "format"})
```

### Rescue Mapping

Map third-party exceptions to structured `Dex::Error` codes declaratively, eliminating boilerplate `begin/rescue/error!` blocks.

```ruby
class ChargeCard < Dex::Operation
  rescue_from Stripe::CardError,      as: :card_declined
  rescue_from Stripe::RateLimitError, as: :rate_limited
  rescue_from Stripe::APIError,       as: :provider_error, message: "Stripe is down"
  rescue_from Net::OpenTimeout, Net::ReadTimeout, as: :timeout  # multiple classes

  def perform
    Stripe::Charge.create(amount: amount, source: token)
  end
end
```

Options:
- `as:` (required) — the `Dex::Error` code
- `message:` (optional) — overrides the original exception's message; uses exception's message by default

The original exception is always available in `details[:original]`. `Dex::Error` (from `error!`) passes through untouched. Unregistered exceptions propagate normally. Works naturally with `.safe`, pattern matching, transactions, and recording.

### Outcome Handling

Use `.safe` to return `Ok`/`Err` instead of raising exceptions. Perfect for pattern matching.

```ruby
class FindUser < Dex::Operation
  params do
    attribute :user_id, Types::Integer
  end

  result do
    attribute :user, Types::Hash
  end

  def perform
    user = User.find_by(id: user_id)
    error!(:not_found, "User not found") unless user

    {user: user.as_json}
  end
end

# Include Dex::Match for cleaner pattern matching syntax
include Dex::Match

outcome = FindUser.new(user_id: 123).safe.call

case outcome
in Ok(user:)
  puts "Found: #{user['name']}"
in Err(code: :not_found)
  puts "User not found"
end
```

Check outcome status:

```ruby
outcome.ok?      # => true/false
outcome.error?   # => true/false
outcome.value    # => result or nil
outcome.code     # => error code (Err only)
outcome.message  # => error message (Err only)
```

### Recording

Record operation calls to database. Supports ActiveRecord and Mongoid.

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  config.record_class = OperationRecord
end
```

```ruby
# migration
create_table :operation_records do |t|
  t.string :name, null: false      # Required: operation class name
  t.jsonb :params, default: {}     # Optional: operation params
  t.jsonb :response                # Optional: operation response/result
  t.string :status                 # Optional: pending/running/done/failed (for async+recording)
  t.string :error                  # Optional: error code on failure (for async+recording)
  t.datetime :performed_at         # Optional: execution timestamp
  t.timestamps
end
```

By default, both params and response are recorded. Granular control:

```ruby
class SensitiveOperation < Dex::Operation
  record false                     # Disable recording entirely
end

class LargeResponseOperation < Dex::Operation
  record response: false           # Save params, skip response
end

class AuditOperation < Dex::Operation
  record params: false             # Save response, skip params
end
```

### Async + Recording Integration

When both async execution and recording are enabled (with params recording), Dexkit automatically optimizes Redis usage by storing only a record ID in the job payload instead of the full params hash. This is selected automatically — no new DSL needed.

| Condition | Job class | Redis payload |
|-----------|-----------|---------------|
| Recording enabled + params recorded | `RecordJob` | `{ class_name:, record_id: }` |
| Everything else | `DirectJob` | `{ class_name:, params: {} }` |

The record tracks status through its lifecycle: `pending` → `running` → `done` / `failed`. On failure, the `error` field captures the error code (`Dex::Error`) or exception class name.

```ruby
# Sync calls also set status: "done" when status column exists
MyOp.new(name: "test").call
# OperationRecord: status: "done"

# Async with recording: record-based strategy
MyOp.new(name: "test").async.call
# OperationRecord: status: "pending" → "running" → "done"/"failed"
```

### Callbacks

Hook into the operation lifecycle with `before`, `after`, and `around`. Callbacks run inside the transaction boundary, so errors trigger rollback.

```ruby
class ProcessOrder < Dex::Operation
  before :validate_stock          # symbol — calls method
  before -> { log("starting") }   # lambda
  before { log("starting") }      # block

  after :send_confirmation        # runs after perform succeeds
  after -> { log("done") }

  around :with_timing             # symbol — method uses yield
  around ->(cont) { cont.call }   # proc — receives continuation

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

**Behavior:**
- `before` callbacks run in order before `perform`. Calling `error!` stops execution.
- `after` callbacks run in order after `perform` succeeds. Skipped if `perform` raises.
- `around` wraps the entire before/perform/after sequence. If the callback doesn't yield/call the continuation, `perform` is never invoked.
- Callbacks inherit from parent classes (parent runs first).
- Blocks and lambdas execute via `instance_exec`, giving access to `params`, `error!`, etc.

### Transactions

Operations run inside database transactions by default. Changes are rolled back on errors.

```ruby
class CreateOrder < Dex::Operation
  def perform
    Order.create!(...)
    LineItem.create!(...)
    # Both rolled back if error occurs
  end
end
```

Opt out for read-only operations:

```ruby
class ReadOnlyOperation < Dex::Operation
  transaction false
  # ...
end
```

Configure adapter globally (default: `:active_record`):

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  config.transaction_adapter = :mongoid
end
```

Override per-operation:

```ruby
class MongoidOperation < Dex::Operation
  transaction adapter: :mongoid
  # or shorthand:
  transaction :mongoid
  # ...
end
```

### Settings

Generic class-level configuration with inheritance.

```ruby
class BaseOperation < Dex::Operation
  set :retry, attempts: 3, delay: 5
end

class ChildOperation < BaseOperation
  set :retry, delay: 10  # inherits attempts: 3, overrides delay
end

ChildOperation.settings_for(:retry)
# => { attempts: 3, delay: 10 }
```

## Types

Uses [dry-types](https://dry-rb.org/gems/dry-types). Define in your app:

```ruby
module Types
  include Dry.Types(default: :nominal)
  extend Dex::Types::Extension
end
```

### Record Types

`Types::Record(ModelClass)` accepts model instances or IDs, automatically finding records from the database. Perfect for working with ActiveRecord or Mongoid models in operations.

```ruby
class SendEmail < Dex::Operation
  params do
    attribute :user, Types::Record(User)
  end

  def perform
    # user is an actual User instance
    Mailer.welcome(user).deliver_later
  end
end

# Both work - pass instance or ID
SendEmail.new(user: User.find(123)).call
SendEmail.new(user: 123).call
```

Works in result blocks too:

```ruby
class FindUser < Dex::Operation
  result do
    attribute :user, Types::Record(User)
    attribute :status, Types::String
  end

  def perform
    user = User.find_by(id: user_id)
    error!(:not_found) unless user

    { user: user, status: 'active' }
  end
end

result = FindUser.new(user_id: 123).call
result.user.name  # => "John Doe" (actual User instance)
```

Optional records:

```ruby
class UpdateProfile < Dex::Operation
  params do
    attribute :user, Types::Record(User)
    attribute :avatar, Types::Record(Avatar).optional
  end
end

UpdateProfile.new(user: 1, avatar: nil).call  # avatar can be nil
```

Lock records on fetch with `lock: true` (uses `SELECT ... FOR UPDATE`):

```ruby
class TransferFunds < Dex::Operation
  params do
    attribute :account, Types::Record(Account, lock: true)
  end

  def perform
    account.update!(balance: account.balance - 100)
  end
end

TransferFunds.new(account: 42).call  # Account.lock.find(42)
```

When recording to database, Record types serialize as IDs (not full objects):

```ruby
# params.as_json => {"user" => 123, "avatar" => 456}
# Keeps your operation_records table clean and efficient
```

## AI Coding Assistant Setup

Dexkit provides LLM-optimized documentation for AI coding agents. Copy the guide to your operations directory so agents automatically know the complete API when working on operations.

**Setup:**

```bash
cp $(bundle show dexkit)/guides/llm/OPERATION.md app/operations/CLAUDE.md
# or for other AI assistants:
cp $(bundle show dexkit)/guides/llm/OPERATION.md app/operations/AGENTS.md
```

The guide contains comprehensive documentation of all Operation features, optimized for AI comprehension. Commit it to your repository and customize with project-specific conventions.

**Benefits:**
- Agents automatically load Operation knowledge when working in `app/operations/`
- Documentation matches your installed dexkit version
- Extend with project-specific patterns and conventions

## License

MIT
