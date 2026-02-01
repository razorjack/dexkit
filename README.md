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
