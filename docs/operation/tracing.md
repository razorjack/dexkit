---
description: Automatic execution tracing for Dex::Operation – Stripe-style IDs, fiber-local trace stacks, actor tracking, and async propagation.
---

# Tracing

Every operation automatically gets a unique execution ID and participates in a fiber-local trace stack. No opt-in needed – tracing is always on.

## How it works

When an operation runs, `TraceWrapper` (the outermost pipeline step):

1. Generates a Stripe-style execution ID (`op_...`)
2. Auto-starts a trace if none exists (generates a `tr_...` trace ID)
3. Pushes a frame onto the trace stack
4. Runs the pipeline
5. Pops the frame on exit

Nested operations share the same trace. The trace stack captures the full call chain.

## Starting a trace

In a controller, middleware, or job wrapper, seed the trace with actor info:

```ruby
class ApplicationController < ActionController::Base
  around_action :dex_trace

  private

  def dex_trace(&block)
    Dex::Trace.start(
      actor: { type: :user, id: current_user.id },
      trace_id: request.request_id,
      &block
    )
  end
end
```

Everything inside the block shares the same `trace_id`. Operations push `:operation` frames, handlers push `:handler` frames, and events capture the current `trace_id` in their metadata.

The `actor` hash requires a `type` key – Dex doesn't interpret the contents beyond that. Common actor types:

| Type | Who | Example |
|---|---|---|
| `:user` | Authenticated human | `{ type: :user, id: 42 }` |
| `:admin` | Privileged human | `{ type: :admin, id: 5 }` |
| `:agent` | AI / LLM agent | `{ type: :agent, name: "support-bot" }` |
| `:api_key` | External API consumer | `{ type: :api_key, id: "key_live_abc" }` |
| `:webhook` | Inbound webhook | `{ type: :webhook, source: "stripe" }` |
| `:system` | Background / cron | `{ type: :system, name: "nightly_cleanup" }` |

These are conventions, not enforced types. Use whatever makes sense for your app.

`Dex.system` is a convenience helper for background jobs and cron:

```ruby
Dex::Trace.start(actor: Dex.system("nightly_cleanup")) do
  Order::Cleanup.call
end

Dex.system               # => { type: :system }
Dex.system("payroll")    # => { type: :system, name: "payroll" }
```

If an operation runs outside a `Dex::Trace.start` block, a trace starts automatically with no actor. Tracing works even without explicit setup – it just lacks an actor root.

`Dex::Trace.start` is designed for the outermost boundary. If called inside an existing trace, the outer trace is suspended for the duration of the block and restored afterward – the inner block gets a fresh trace.

## Reading the trace

Inside `perform` or any code within the trace:

```ruby
class Order::Place < Dex::Operation
  def perform
    Dex::Trace.trace_id     # => "tr_..." or external ID
    Dex::Trace.current_id   # => "op_..." (this operation's ID)
    Dex::Trace.current      # => [actor_frame, parent_op_frame, this_op_frame]
    Dex::Trace.to_s         # => "user:123 > Order::Validate(op_2nFg7K) > Order::Place(op_3kPm8N)"

    Dex.actor               # => { type: "user", id: "123" } or nil
  end
end
```

`Dex.actor` returns the actor hash in the same shape you passed in (with string values), or `nil` when no actor was set. It's the complement to `Dex.context` – same level of abstraction, no need to know about `Dex::Trace`.

Most operations won't need this – actor is captured automatically by recording. Use `Dex.actor` when you need to write actor info into your own domain models:

```ruby
class Order::Place < Dex::Operation
  def perform
    Order.create!(
      product: product,
      placed_by_type: Dex.actor&.dig(:type),
      placed_by_id: Dex.actor&.dig(:id)
    )
  end
end
```

## ID format

Stripe-style prefixed IDs with embedded timestamp for sortability:

| Prefix | Type | Length |
|---|---|---|
| `op_` | Operation execution | 23 chars |
| `ev_` | Event instance | 23 chars |
| `hd_` | Handler execution | 23 chars |
| `tr_` | Trace (correlation) | 23 chars |

Base58 encoded (Bitcoin alphabet). Time-ordered within the same prefix – `ORDER BY id` gives chronological order.

## Recording integration

When recording is enabled, trace data is automatically included in operation records via `safe_attributes`. Add these optional columns to your recording table:

```ruby
# In your migration
create_table :operation_records, id: :string do |t|
  # ... other columns ...
  t.string :trace_id, limit: 40                              # tr_... or external
  t.string :actor_type, limit: 50
  t.string :actor_id, limit: 100
  t.jsonb :trace                                             # full trace array
end

add_index :operation_records, :trace_id
add_index :operation_records, [:actor_type, :actor_id]
```

If these columns don't exist, trace data is silently omitted – existing tables work without migration.

### Querying patterns

```ruby
# All operations in a request
OperationRecord.where(trace_id: "tr_8pVq3R7d1wHxZ4aBcD").order(:id)

# All operations by a user
OperationRecord.where(actor_type: "user", actor_id: "123").order(:id)

# Reconstruct the call tree
records = OperationRecord.where(trace_id: trace_id).order(:id)
records.each do |r|
  depth = r.trace.count { |f| f["type"] == "operation" } - 1
  puts "#{"  " * depth}#{r.name} [#{r.status}] #{r.id}"
end
```

## Async propagation

Trace context is automatically serialized into async job payloads and restored when the job runs. Background operations become continuations of the original trace:

```ruby
class Order::Place < Dex::Operation
  def perform
    order = Order.create!(product: product)
    Order::SendConfirmation.new(order_id: order.id).async.call
    order
  end
end

# When the job runs (possibly minutes later, different process):
# Order::SendConfirmation's trace includes the original actor and Order::Place frame.
# Same trace_id, same actor.
```

## Actor patterns

The actor hash is opaque – Dex stores what you pass. These patterns cover the most common scenarios:

### Admin impersonation

Who is the actor – the admin or the impersonated user? It depends on what your audit trail needs to answer:

```ruby
# "Which admin actions should we review?" – admin is actor
Dex::Trace.start(actor: { type: :admin, id: admin.id, on_behalf_of: customer.id }) do
  Dex.with_context(current_customer: customer) do
    Order::Place.call(product: product, customer: customer, quantity: 1)
  end
end

# "What happened on my account?" – user is actor
Dex::Trace.start(actor: { type: :user, id: customer.id, impersonated_by: admin.id }) do
  Order::Place.call(product: product, customer: customer, quantity: 1)
end
```

Neither is universally correct. Pick one and be consistent.

### AI agents

When a user asks a chatbot to perform an action, the user is still the actor – the agent is the channel:

```ruby
# User-initiated, agent-assisted
Dex::Trace.start(actor: { type: :user, id: user.id, via: "support-bot" }) do
  Order::Place.call(product: product)
end
```

`via` captures how the action happened – works for any mechanism, not just AI:

```ruby
{ type: :user, id: 42 }                          # web (direct)
{ type: :user, id: 42, via: "support-bot" }       # chatbot
{ type: :user, id: 42, via: "zapier" }            # integration
{ type: :user, id: 42, via: "ios" }               # mobile app
```

Use `:agent` when there's no human in the loop – autonomous agents acting on policy:

```ruby
Dex::Trace.start(actor: { type: :agent, name: "content-writer" }) do
  Content::Generate.call(topic: topic)
end
```

### Background jobs

```ruby
class ApplicationJob < ActiveJob::Base
  around_perform do |job, block|
    Dex::Trace.start(actor: Dex.system(job.class.name), &block)
  end
end
```

## PaperTrail integration

```ruby
# config/initializers/paper_trail.rb
PaperTrail.config.whodunnit_callable = -> { Dex::Trace.to_s.presence }

# Later:
version.whodunnit
# => "user:42 > Order::Place(op_3kPm8N) > Order::Charge(op_5kRo0N)"
```
