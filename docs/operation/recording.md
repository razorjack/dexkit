---
description: Persist Dex::Operation runs for auditing and debugging with ActiveRecord or Mongoid recording models and serialized params and results.
---

# Recording

Record operation executions to a database table for auditing, debugging, or analytics. Supports ActiveRecord and Mongoid.

## Setup

Create a model and table for storing records:

```ruby
# migration
create_table :operation_records do |t|
  t.string :name, null: false        # operation class name
  t.jsonb :params                     # serialized props (nil = not captured)
  t.jsonb :result                     # serialized return value
  t.string :status, null: false       # pending/running/completed/error/failed
  t.string :error_code                # Dex::Error code or exception class
  t.string :error_message             # human-readable message
  t.jsonb :error_details              # structured details hash
  t.datetime :performed_at            # execution completion timestamp
  t.timestamps
end

add_index :operation_records, :name
add_index :operation_records, :status
add_index :operation_records, [:name, :status]
```

```ruby
# app/models/operation_record.rb
class OperationRecord < ApplicationRecord
end
```

Then configure dexkit:

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  config.record_class = OperationRecord
end
```

All columns except `name` and `status` are optional – dexkit only writes to columns that exist on the model. Add what you need, leave out what you don't.

## What gets recorded

All outcomes are recorded – success, business errors, and exceptions:

```ruby
class Employee::Onboard < Dex::Operation
  prop :email, String
  prop :name, String

  def perform
    Employee.create!(email: email, name: name)
  end
end

Employee::Onboard.call(email: "alice@example.com", name: "Alice")
# OperationRecord:
#   name: "Employee::Onboard"
#   params: { "email" => "alice@example.com", "name" => "Alice" }
#   result: { "id" => 1, "email" => "alice@example.com", ... }
#   status: "completed"
#   performed_at: 2024-01-15 10:30:00
```

Ref types (`_Ref(Customer)`) serialize as IDs in both params and result, keeping records clean and compact.

## Status values

| Status | Meaning |
|---|---|
| `pending` | Async job enqueued, not started |
| `running` | Async job picked up, executing |
| `completed` | `perform` returned successfully |
| `error` | Business error via `error!` |
| `failed` | Unhandled exception |

Business errors populate `error_code`, `error_message`, and `error_details`:

```ruby
class Order::Place < Dex::Operation
  prop :order_id, Integer
  error :out_of_stock

  def perform
    error!(:out_of_stock, "Item unavailable", details: { sku: "ABC-123" })
  end
end

# OperationRecord:
#   status: "error"
#   error_code: "out_of_stock"
#   error_message: "Item unavailable"
#   error_details: { "sku" => "ABC-123" }
```

Exceptions populate `error_code` (exception class name) and `error_message`.

## Controlling what's recorded

```ruby
class Employee::ProcessPayroll < Dex::Operation
  record false                # disable recording entirely
end

class Order::ExportBatch < Dex::Operation
  record result: false        # record params only
end

class Employee::Audit < Dex::Operation
  record params: false        # record result only
end
```

## Success type and result

When `success Type` is declared, dexkit serializes the result intelligently:

```ruby
class Employee::Find < Dex::Operation
  success _Ref(Employee)

  def perform
    Employee.find(employee_id)
  end
end

# result is stored as just the employee ID, not the full serialized object
```

For other return types, the result is stored as-is (Hash), or wrapped in `{ value: ... }` for scalar values.

## Transaction behavior

Recording runs outside the operation's own transaction. Error and failure records survive the operation's transaction rollback – you always have a record of what happened, even when the operation's side effects are rolled back.

If the operation runs inside an ambient transaction (e.g., called from another operation, or wrapped in `ActiveRecord::Base.transaction { ... }`), the record participates in that outer transaction and will be rolled back with it. This is consistent with Rails conventions – if the entire ambient transaction fails, neither the operation's effects nor its record persist. If you need recording to survive ambient rollbacks, configure your record model with a [separate database connection](https://guides.rubyonrails.org/active_record_multiple_databases.html).

## Async integration

When combined with [Async](/operation/async), recording provides status tracking across the operation's lifecycle. See the [Async page](/operation/async#recording-integration) for details.

## Anonymous operations

Operations without a class name (anonymous classes) are not recorded, since there's no meaningful `name` to store.
