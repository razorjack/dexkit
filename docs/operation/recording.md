---
description: Dex::Operation recording — persist every run to the database with params, results, errors, and timing for auditing and debugging.
---

# Recording

Record operation executions to a database table for auditing, debugging, or analytics. Works with both ActiveRecord and Mongoid recording models.

## Setup

Create a recording model with the fields required by the recording features you enable.

### ActiveRecord

Create a model and table:

```ruby
# migration
create_table :operation_records, id: :string do |t|
  t.string :name, null: false     # operation class name
  t.string :trace_id              # shared trace / correlation ID
  t.string :actor_type            # root actor type
  t.string :actor_id              # root actor ID
  t.jsonb :trace                  # full trace snapshot
  t.jsonb :params                 # serialized props (nil = not captured)
  t.jsonb :result                 # serialized return value
  t.string :status, null: false   # completed/error/failed/pending/running
  t.string :error_code            # Dex::Error code or exception class
  t.string :error_message         # human-readable message
  t.jsonb :error_details          # structured details hash
  t.datetime :performed_at        # execution completion timestamp
  t.timestamps
end

add_index :operation_records, :name
add_index :operation_records, :status
add_index :operation_records, [:name, :status]
add_index :operation_records, :trace_id
add_index :operation_records, [:actor_type, :actor_id]
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

  field :_id, type: String, default: -> { Dex::Id.generate("op_") }
  field :name, type: String
  field :trace_id, type: String
  field :actor_type, type: String
  field :actor_id, type: String
  field :trace, type: Array
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

Trace columns (`id`, `trace_id`, `actor_type`, `actor_id`, `trace`) are recommended but optional – Dex persists them when present and silently omits them when they're missing. This means you can adopt tracing incrementally: the in-memory trace works immediately, and persistence comes when you add the columns.

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
#   id: "op_..."
#   trace_id: "tr_..."
#   actor_type: "user"              (when Dex::Trace.start sets an actor)
#   actor_id: "42"
#   trace: [{ "type" => "actor", ... }, { "type" => "operation", ... }]
#   name: "Employee::Onboard"
#   params: { "email" => "alice@example.com", "name" => "Alice" }
#   result: { "id" => 1, "email" => "alice@example.com", ... }
#   status: "completed"
#   performed_at: 2024-01-15 10:30:00
```

Ref types (`_Ref(Customer)`) serialize as IDs in both params and result, keeping records clean and compact. Mongoid `BSON::ObjectId` values are serialized safely too.

## Trace integration

Recording uses the current `Dex::Trace` snapshot. When an actor is set, the record captures who initiated the chain:

```ruby
Dex::Trace.start(actor: { type: :user, id: 42 }) do
  Order::Place.call(order_id: 1)
end

record = OperationRecord.last
record.trace_id    # => "tr_..."
record.actor_type  # => "user"
record.actor_id    # => "42"
record.trace       # => full actor > operation ancestry
```

The `trace` column carries the complete call stack at the time of execution – every parent frame is included. Combined with `trace_id`, this makes it straightforward to reconstruct the full call tree for any request.

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

In Mongoid-only apps, where no transaction adapter is active, recording still works – records are persisted normally, and `after_commit` callbacks fire immediately after the pipeline succeeds.

## Async integration

When combined with [Async](/operation/async), recording provides status tracking across the operation's lifecycle. See the [Async page](/operation/async#recording-integration) for details.

## Anonymous operations

Operations without a class name (anonymous classes) are not recorded, since there's no meaningful `name` to store.
