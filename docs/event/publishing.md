---
description: Publish Dex::Event instances synchronously or asynchronously, pass metadata, and control dispatch behavior.
---

# Publishing Events

## Class-level publish

The most common way to publish:

```ruby
Order::Placed.publish(order_id: 1, total: 99.99)              # async (default)
Order::Placed.publish(order_id: 1, total: 99.99, sync: true)   # sync
```

## Instance-level publish

Create the event first, then publish:

```ruby
event = Order::Placed.new(order_id: 1, total: 99.99)
event.publish                    # async
event.publish(sync: true)        # sync
```

Useful when you need the event object first (for example, to pass it as `caused_by:`).

## Sync vs async

**Async** (default): Each handler is dispatched as an ActiveJob. Handlers run independently — one failure doesn't affect others. If ActiveJob is not loaded, `publish(sync: false)` raises `LoadError`.

**Sync**: Handlers called inline in the current thread. Useful for tests and when you need immediate execution.

## Caused by

Link an event to its cause:

```ruby
order_event = Order::Placed.new(order_id: 1, total: 99.99)
Shipment::Reserved.publish(order_id: 1, caused_by: order_event)
```

The child event's `caused_by_id` is set to the parent's `id`, and they share the same `trace_id`. When an event is published inside a handler, Dex sets the cause automatically from the handler's event. See [Tracing](./tracing) for details.

## Context

Events support the same `context` DSL as operations. Context-mapped props are resolved at **publish time** and stored as regular props on the event – handlers don't need ambient context because the event carries everything:

```ruby
class Order::Placed < Dex::Event
  prop :order_id, Integer
  prop :customer, _Ref(Customer)
  context customer: :current_customer
end

# Inside a Dex.with_context block, customer is auto-filled:
Dex.with_context(current_customer: customer) do
  Order::Placed.publish(order_id: 1)
end

# Or pass explicitly – no context needed:
Order::Placed.publish(order_id: 1, customer: customer)
```

See [Ambient Context](/operation/context#events) for the full story.

## What happens on publish

1. Check [suppression](./tracing#suppression) — skip if suppressed
2. Persist to `event_store` if configured (failure doesn't halt)
3. Find subscribed handlers
4. Serialize the current trace for async dispatch (or restore it inline for sync)
5. Dispatch each handler (async or sync)
