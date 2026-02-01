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

outcome = FindUser.new(user_id: 123).safe.perform

case outcome
in Dex::Ok(user:)
  puts "Found: #{user['name']}"
in Dex::Err(code: :not_found)
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
  t.datetime :performed_at         # Optional: execution timestamp
  t.timestamps
end
```

Disable recording per-class:

```ruby
class SensitiveOperation < Dex::Operation
  record false
  # ...
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
end
```

## License

MIT
