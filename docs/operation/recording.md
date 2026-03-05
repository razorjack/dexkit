# Recording

Record operation executions to a database table for auditing, debugging, or analytics. Supports ActiveRecord and Mongoid.

## Setup

Create a model and table for storing records:

```ruby
# migration
create_table :operation_records do |t|
  t.string :name, null: false   # operation class name
  t.jsonb :params, default: {}   # operation properties
  t.jsonb :response                    # return value
  t.string :status                      # pending/running/done/failed
  t.string :error                       # error code on failure
  t.datetime :performed_at               # execution timestamp
  t.timestamps
end
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

All columns except `name` are optional – dexkit only writes to columns that exist on the model. Add what you need, leave out what you don't.

## What gets recorded

By default, both params and the response are recorded:

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
#   response: { "id" => 1, "email" => "alice@example.com", ... }
#   status: "done"
#   performed_at: 2024-01-15 10:30:00
```

Ref types (`_Ref(Customer)`) serialize as IDs in both params and response, keeping records clean and compact.

## Controlling what's recorded

```ruby
class Employee::ProcessPayroll < Dex::Operation
  record false                # disable recording entirely
end

class Order::ExportBatch < Dex::Operation
  record response: false      # record params only
end

class Employee::Audit < Dex::Operation
  record params: false        # record response only
end
```

## Success type and response

When `success Type` is declared, dexkit serializes the response intelligently:

```ruby
class Employee::Find < Dex::Operation
  success _Ref(Employee)

  def perform
    Employee.find(employee_id)
  end
end

# response is stored as just the employee ID, not the full serialized object
```

For other return types, the response is stored as-is (Hash), or wrapped in `{ value: ... }` for scalar values.

## Async integration

When combined with [Async](/operation/async), recording provides status tracking across the operation's lifecycle. See the [Async page](/operation/async#recording-integration) for details.

## Anonymous operations

Operations without a class name (anonymous classes) are not recorded, since there's no meaningful `name` to store.
