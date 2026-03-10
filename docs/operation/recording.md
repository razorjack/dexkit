---
description: Persist Dex::Operation runs for auditing and debugging with ActiveRecord or Mongoid recording models and serialized params and results.
---

# Recording

Record operation executions to a database table for auditing, debugging, or analytics. Supports ActiveRecord and Mongoid.

## Setup

Create a recording model with the fields required by the recording features you enable.

### ActiveRecord

Create a model and table:

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

### Mongoid

Mongoid recording models work too. Define matching fields and add the same sparse unique `once_key` index if you use `once`:

```ruby
class OperationRecord
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :params, type: Hash
  field :result, type: Hash
  field :status, type: String
  field :error_code, type: String
  field :error_message, type: String
  field :error_details, type: Hash
  field :performed_at, type: Time
  field :once_key, type: String
  field :once_key_expires_at, type: Time

  index({ name: 1 })
  index({ status: 1 })
  index({ name: 1, status: 1 })
  index({ once_key: 1 }, unique: true, sparse: true)
end
```

Then configure dexkit:

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  config.record_class = OperationRecord
end
```

dexkit validates the configured record model before using it and raises if required attributes are missing.

Required attributes by feature:

- Core recording: `name`, `status`, `error_code`, `error_message`, `error_details`, `performed_at`
- Params capture: `params` unless `record params: false`
- Result capture: `result` unless `record result: false`
- Async record jobs: `params`
- `once`: `once_key`, plus `once_key_expires_at` when `expires_in:` is used

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

Ref types (`_Ref(Customer)`) serialize as IDs in both params and result, keeping records clean and compact. Mongoid `BSON::ObjectId` values are serialized safely too.

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

For other return types, dexkit stores a JSON-safe version of the value. Plain Hash results round-trip as Hashes (with string keys after persistence), and scalar or object results are wrapped under `"_dex_value"`. Objects that respond to `as_json` use that representation.

## Transaction behavior

Recording runs outside the operation's own transaction. Error and failure records survive the operation's transaction rollback – you always have a record of what happened, even when the operation's side effects are rolled back.

If the operation runs inside an ambient transaction (e.g., called from another operation, or wrapped in `ActiveRecord::Base.transaction { ... }`), the record participates in that outer transaction and will be rolled back with it. This is consistent with Rails conventions – if the entire ambient transaction fails, neither the operation's effects nor its record persist. If you need recording to survive ambient rollbacks, configure your record model with a [separate database connection](https://guides.rubyonrails.org/active_record_multiple_databases.html).

For Mongoid, Dex-managed transactions work the same way once you opt in with `config.transaction_adapter = :mongoid` or `transaction :mongoid`. Ambient `Mongoid.transaction` blocks opened outside Dex are not supported for Dex `after_commit` callbacks – Dex raises instead of firing those callbacks early.

## Async integration

When combined with [Async](/operation/async), recording provides status tracking across the operation's lifecycle. See the [Async page](/operation/async#recording-integration) for details.

## Anonymous operations

Operations without a class name (anonymous classes) are not recorded, since there's no meaningful `name` to store.
