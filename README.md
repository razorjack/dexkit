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
    user = User.find(params.user_id)
    Mailer.welcome(user, template: params.template).deliver_later
  end
end

SendWelcomeEmail.new(user_id: 123).perform
```

### Async Execution

Requires ActiveJob. Enqueue operations as background jobs.

```ruby
# Enqueue immediately
SendWelcomeEmail.new(user_id: 123).async.perform

# With options
SendWelcomeEmail.new(user_id: 123).async(queue: "low").perform
SendWelcomeEmail.new(user_id: 123).async(in: 5.minutes).perform
SendWelcomeEmail.new(user_id: 123).async(at: 1.hour.from_now).perform

# Class-level defaults
class SendWelcomeEmail < Dex::Operation
  async queue: "mailers"
  # ...
end
```

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
    user = User.create!(email: params.email, name: params.name)
    {user_id: user.id, status: "created"}
  end
end

result = CreateUser.new(email: "user@example.com", name: "John").perform
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
    if params.amount < 0
      error!(:invalid_amount, "Amount must be positive")
    end

    # Process payment...
  end
end

ProcessPayment.new(amount: -100).perform
# raises Dex::Error with code: :invalid_amount
```

Add details to errors:

```ruby
error!(:validation_failed, "Invalid data", details: {field: "email", issue: "format"})
```

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
    user = User.find_by(id: params.user_id)
    error!(:not_found, "User not found") unless user

    {user: user.as_json}
  end
end

# Include Dex::Match for cleaner pattern matching syntax
include Dex::Match

outcome = FindUser.new(user_id: 123).safe.perform

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
    # params.user is an actual User instance
    Mailer.welcome(params.user).deliver_later
  end
end

# Both work - pass instance or ID
SendEmail.new(user: User.find(123)).perform
SendEmail.new(user: 123).perform
```

Works in result blocks too:

```ruby
class FindUser < Dex::Operation
  result do
    attribute :user, Types::Record(User)
    attribute :status, Types::String
  end

  def perform
    user = User.find_by(id: params.user_id)
    error!(:not_found) unless user

    { user: user, status: 'active' }
  end
end

result = FindUser.new(user_id: 123).perform
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

UpdateProfile.new(user: 1, avatar: nil).perform  # avatar can be nil
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
