# Async

Run operations in the background via ActiveJob. Properties are serialized to JSON, enqueued, and deserialized when the job executes.

## Basic usage

```ruby
SendWelcomeEmail.new(user_id: 123).async.call
```

That's it – the operation is enqueued as an ActiveJob and runs in the background. ActiveJob must be available (it ships with Rails).

## Scheduling options

```ruby
# Run on a specific queue
SendWelcomeEmail.new(user_id: 123).async(queue: "mailers").call

# Run after a delay
SendWelcomeEmail.new(user_id: 123).async(in: 5.minutes).call

# Run at a specific time
SendWelcomeEmail.new(user_id: 123).async(at: 1.hour.from_now).call
```

## Class-level defaults

Set default async options for all instances:

```ruby
class SendWelcomeEmail < Dex::Operation
  async queue: "mailers"

  prop :user_id, Integer

  def perform
    UserMailer.welcome(user_id).deliver_now
  end
end

# Uses the "mailers" queue by default
SendWelcomeEmail.new(user_id: 123).async.call

# Runtime options override class defaults
SendWelcomeEmail.new(user_id: 123).async(queue: "urgent").call
```

## Serialization

All properties must be JSON-serializable for async execution. Dexkit validates this at enqueue time – non-serializable properties raise `ArgumentError` immediately, not when the job runs.

Types that survive the JSON round-trip automatically:

| Type | Serialized as | Deserialized back to |
|---|---|---|
| `String`, `Integer`, `Float`, `Boolean`, `nil` | themselves | themselves |
| `Symbol` | String | Symbol |
| `Time`, `Date`, `DateTime` | ISO 8601 String | parsed back |
| `BigDecimal` | String | BigDecimal |
| `_Ref(Model)` | model ID | found via `Model.find(id)` |
| `Hash`, `Array` | JSON | Hash/Array with coerced values |

You don't need to change your prop types for async – the same operation works for both sync and async calls.

## Recording integration

When [Recording](/operation/recording) is enabled with params, async automatically optimizes Redis usage. Instead of serializing the full params hash into the job payload, it stores a record ID and retrieves params from the database:

| Condition | Job strategy | Payload |
|---|---|---|
| Recording enabled + params recorded | `RecordJob` | `{ class_name, record_id }` |
| Everything else | `DirectJob` | `{ class_name, params }` |

This is selected automatically – no configuration needed. The record tracks status through its lifecycle:

```
pending > running > done
                  > failed
```

```ruby
# Async + recording: the record is created immediately, job enqueued
SendReport.new(user_id: 123).async.call
# OperationRecord: status: "pending"
# → job runs → status: "running"
# → success  → status: "done"
# → failure  → status: "failed", error: "error_code"
```

## Error handling

If the job fails, the exception propagates normally through ActiveJob's retry mechanism. When recording is enabled, the record's status is set to `"failed"` and the error field captures either the `Dex::Error` code or the exception class name.
