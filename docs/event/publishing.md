# Publishing Events

## Class-level publish

The most common way to publish:

```ruby
OrderPlaced.publish(order_id: 1, total: 99.99)              # async (default)
OrderPlaced.publish(order_id: 1, total: 99.99, sync: true)   # sync
```

## Instance-level publish

Create the event first, then publish:

```ruby
event = OrderPlaced.new(order_id: 1, total: 99.99)
event.publish                    # async
event.publish(sync: true)        # sync
```

Useful when you need the event object (e.g., for tracing).

## Sync vs async

**Async** (default): Each handler is dispatched as an ActiveJob. Handlers run independently — one failure doesn't affect others.

**Sync**: Handlers called inline in the current thread. Useful for tests and when you need immediate execution.

## Caused by

Link an event to its cause:

```ruby
order_event = OrderPlaced.new(order_id: 1, total: 99.99)
InventoryReserved.publish(order_id: 1, caused_by: order_event)
```

The child event's `caused_by_id` is set to the parent's `id`, and they share the same `trace_id`. See [Tracing](./tracing) for details.

## What happens on publish

1. Check [suppression](./tracing#suppression) — skip if suppressed
2. Persist to `event_store` if configured (failure doesn't halt)
3. Find subscribed handlers
4. Dispatch each handler (async or sync)
