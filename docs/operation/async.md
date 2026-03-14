---
description: Run Dex::Operation classes through ActiveJob – async execution, queue selection, scheduling, and recording integration.
---

# Async

Run operations in the background via ActiveJob. Properties are serialized to JSON, enqueued, and deserialized when the job executes.

## Basic usage

```ruby
Order::SendConfirmation.new(order_id: 123).async.call
```

That's it – the operation is enqueued as an ActiveJob and runs in the background. ActiveJob must be available (it ships with Rails).

## Scheduling options

```ruby
# Run on a specific queue
Order::SendConfirmation.new(order_id: 123).async(queue: "mailers").call

# Run after a delay
Order::SendConfirmation.new(order_id: 123).async(in: 5.minutes).call

# Run at a specific time
Order::SendConfirmation.new(order_id: 123).async(at: 1.hour.from_now).call
```

## Class-level defaults

Set default async options for all instances:

```ruby
class Order::SendConfirmation < Dex::Operation
  async queue: "mailers"

  prop :order_id, Integer

  def perform
    ConfirmationMailer.order(order_id).deliver_now
  end
end

# Uses the "mailers" queue by default
Order::SendConfirmation.new(order_id: 123).async.call

# Runtime options override class defaults
Order::SendConfirmation.new(order_id: 123).async(queue: "urgent").call
```

## Serialization

All properties must be JSON-serializable for async execution. dexkit validates this at enqueue time – non-serializable properties raise `ArgumentError` immediately, not when the job runs.

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

## Trace propagation

Async operations serialize the current `Dex::Trace` and restore it when the job runs. The background execution keeps the same `trace_id`, actor, and parent ancestry – async is transparent to the trace.

If no trace exists when the job runs, a fresh one starts automatically.

## Recording integration

When [Recording](/operation/recording) is enabled with params, async automatically optimizes Redis usage. Instead of serializing the full params hash into the job payload, it stores a record ID and retrieves params from the database:

| Condition | Job strategy | Payload |
|---|---|---|
| Recording enabled + params recorded | `RecordJob` | `{ class_name, record_id }` |
| Everything else | `DirectJob` | `{ class_name, params }` |

This is selected automatically – no configuration needed. The record tracks status through its lifecycle:

```
pending > running > completed
                  > error
                  > failed
```

```ruby
# Async + recording: the record is created immediately, job enqueued
Order::SendReport.new(order_id: 123).async.call
# OperationRecord: status: "pending"
# → job runs → status: "running"
# → success  → status: "completed"
# → error!   → status: "error", error_code: "code", error_message: "..."
# → exception → status: "failed", error_code: "RuntimeError", error_message: "..."
```

Dex validates the configured record model before enqueueing a `RecordJob`. Missing required attributes (for example `params`, `status`, or `performed_at`) raise immediately instead of being silently skipped.

## Ticket

`async.call` returns a `Dex::Operation::Ticket` – a structured handle for tracking the operation.

```ruby
ticket = Order::Fulfill.new(order_id: 123).async.call

ticket.id              # => "op_01J5..."
ticket.operation_name  # => "Order::Fulfill"
ticket.status          # => "pending"
ticket.job             # => the enqueued ActiveJob instance
ticket.recorded?       # => true (when recording is enabled)
```

When recording is disabled (or using the direct strategy), `ticket.recorded?` returns `false` and only `job` is available. All record-dependent methods (`id`, `status`, `outcome`, etc.) raise `ArgumentError` with a prescriptive message.

### Predicates

```ruby
ticket.pending?    # status == "pending"
ticket.running?    # status == "running"
ticket.completed?  # status == "completed"
ticket.error?      # status == "error"
ticket.failed?     # status == "failed"
ticket.terminal?   # completed? || error? || failed?
```

### Reload

Refresh the ticket from the database:

```ruby
ticket.reload
ticket.status  # => "completed" (if the job finished)
```

### `to_param`

Tickets work directly in Rails path helpers:

```ruby
redirect_to pending_order_path(ticket)  # uses ticket.id
```

### `as_json`

Ready-made JSON for polling endpoints:

```ruby
render json: ticket
# => { "id": "op_01J5...", "name": "Order::Fulfill", "status": "completed", "result": { ... } }
```

`failed` records are intentionally redacted – exception details stay in logs, not API responses.

### `from_record`

Construct a ticket from any operation record – useful for polling endpoints and admin dashboards:

```ruby
ticket = Dex::Operation::Ticket.from_record(OperationRecord.find(params[:id]))
ticket.status   # => "completed"
ticket.outcome  # => Ok or Err
```

## Outcome reconstruction

`ticket.outcome` reconstructs `Ok` or `Err` from the record's business result – the same types as `.safe.call`:

```ruby
ticket.reload

case ticket.outcome
in Dex::Ok(url:)
  redirect_to url
in Dex::Err(code:, message:)
  flash[:error] = message
  redirect_to order_path(@order)
else
  # pending, running, or failed – no business outcome
  render :pending
end
```

| Record status | `outcome` returns | Rationale |
|---|---|---|
| `completed` | `Ok(result)` | Success – result with symbolized keys |
| `error` | `Err(Dex::Error)` | Business error with symbolized code and details |
| `failed` | `nil` | Infrastructure crash – no business outcome |
| `pending` / `running` | `nil` | Not yet resolved |

`outcome` never raises, never reloads. Call `reload` first if you need fresh data.

## Speculative sync (wait / wait!)

Enqueue an async operation, then wait briefly to see if it finishes. If it completes in time, proceed as if synchronous. If not, fall back to async UX.

### `wait` – safe mode (Ok / Err / nil)

```ruby
ticket = Order::SendReport.new(order_id: 123).async.call

case ticket.wait(3.seconds)
in Dex::Ok(url:)
  redirect_to url
in Dex::Err(code:, message:)
  flash[:error] = message
  redirect_to order_path(@order)
else
  redirect_to pending_path(ticket)
end
```

`wait` returns `Ok`, `Err`, or `nil` (timeout). If the operation crashed (infrastructure failure), it raises `Dex::OperationFailed`.

### `wait!` – strict mode (value or exception)

```ruby
ticket = Order::SendReport.new(order_id: 123).async.call
result = ticket.wait!(3.seconds)
redirect_to result[:url]
```

`wait!` returns the unwrapped value on success, raises `Dex::Error` on business error, `Dex::Timeout` on timeout, and `Dex::OperationFailed` on infrastructure crash.

| | Success | Business error | Infra crash | Timeout |
|---|---|---|---|---|
| `call` | value | raises `Dex::Error` | raises exception | n/a |
| `safe.call` | `Ok` | `Err` | raises exception | n/a |
| `wait!(t)` | value | raises `Dex::Error` | raises `OperationFailed` | raises `Dex::Timeout` |
| `wait(t)` | `Ok` | `Err` | raises `OperationFailed` | `nil` |

### Interval options

```ruby
# Fixed interval (default: 200ms)
ticket.wait(3.seconds)

# Faster polling
ticket.wait(2.seconds, interval: 0.05)

# Exponential backoff
ticket.wait(10.seconds, interval: ->(n) { [0.1 * (2**n), 1.0].min })
```

### Threading note

`wait`/`wait!` block the current thread. For short timeouts (2–5 seconds) this is fine. For high-concurrency scenarios, use client-side polling instead. Timeouts above 10 seconds emit a warning.

## Error handling

If the job fails, the exception propagates normally through ActiveJob's retry mechanism. When recording is enabled, the record captures the outcome:

- Business errors (`error!`) set status to `"error"` with `error_code`, `error_message`, and `error_details`
- Unhandled exceptions set status to `"failed"` with `error_code` (exception class) and `error_message`

Three exception types cover async error handling:

- **`Dex::Error`** – business errors from `error!`. Same as sync
- **`Dex::OperationFailed`** – infrastructure crashes (inherits `StandardError`, not `Dex::Error`). Exposes `operation_name`, `exception_class`, `exception_message`
- **`Dex::Timeout`** – wait deadline exceeded (inherits `StandardError`, not `Dex::Error`). Exposes `timeout`, `ticket_id`, `operation_name`

These are categorically distinct – `rescue Dex::Error` never catches crashes or timeouts.

## `safe` and `async` are alternatives

`safe` and `async` are alternative execution strategies, not composable:

```ruby
op.safe.async   # => NoMethodError (prescriptive message)
op.async.safe   # => NoMethodError (prescriptive message)
```

For async, use `wait`/`wait!` on the ticket to get `Ok`/`Err` wrapping.
