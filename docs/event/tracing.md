---
description: Dex::Event tracing and suppression — track event causality with caused_by and event_ancestry, and suppress publication selectively.
---

# Tracing & Suppression

## Causality tracing

Every event gets a unique `ev_`-prefixed ID and a `trace_id`. When events are linked via `caused_by:`, they form a causal chain with a shared `trace_id` (when published within a `Dex::Trace.start` block).

### Using caused_by

```ruby
order_placed = Order::Placed.new(order_id: 1, total: 99.99)

Shipment::Reserved.publish(order_id: 1, caused_by: order_placed)
# caused_by_id = order_placed.id
# event_ancestry = [order_placed.id]
```

### Handler context (automatic)

When a handler publishes an event, the handler's source event automatically becomes `caused_by`:

```ruby
class OnOrderPlaced < Dex::Event::Handler
  on Order::Placed

  def perform
    Shipment::Reserved.publish(order_id: event.order_id)
    # caused_by_id = event.id (automatic)
    # event_ancestry = event.event_ancestry + [event.id]
  end
end
```

### Event ancestry (materialized path)

Every event carries `event_ancestry` – an ordered array of ancestor event IDs. This enables tree-building without traversing `caused_by_id` chains:

```ruby
e1 = Order::Placed.new(order_id: 1, total: 99.99)
e2 = Shipment::Reserved.publish(order_id: 1, caused_by: e1)
e3 = Shipment::Shipped.publish(order_id: 1, caused_by: e2)

e1.event_ancestry  # => []
e2.event_ancestry  # => ["ev_...e1"]
e3.event_ancestry  # => ["ev_...e1", "ev_...e2"]

# Build a materialized path for audit trails
path = (e3.event_ancestry + [e3.id]).join("|")
```

### Metadata

Every event includes:

| Field | Description |
|---|---|
| `id` | Stripe-style `ev_` prefixed ID (23 chars) |
| `timestamp` | UTC time of creation |
| `trace_id` | Shared correlation ID (`tr_` prefixed or external) |
| `caused_by_id` | Parent event's `id` (nil for root events) |
| `event_ancestry` | Array of ancestor event IDs (empty for root events) |
| `context` | Ambient context hash (from config) |

Events share the unified trace stack with operations and handlers – see [Operation Tracing](/operation/tracing) for the full `Dex::Trace` API, actor tracking, and recording integration.

## Suppression

Prevent events from being published. Block-scoped and nestable.

```ruby
# Suppress all events
Dex::Event.suppress do
  Order::Placed.publish(order_id: 1, total: 99.99)  # silently skipped
end

# Suppress specific classes
Dex::Event.suppress(Order::Placed) do
  Order::Placed.publish(order_id: 1, total: 99.99)  # skipped
  Employee::Onboarded.publish(employee_id: 1)        # published normally
end

# Suppress multiple classes
Dex::Event.suppress(Order::Placed, Employee::Onboarded) do
  # both suppressed
end
```

Child event classes are suppressed when their parent class is:

```ruby
class Order::PriorityPlaced < Order::Placed; end

Dex::Event.suppress(Order::Placed) do
  Order::PriorityPlaced.publish(order_id: 1, total: 49.99)  # also suppressed
end
```

Suppression is commonly used in:
- Tests (isolate what you're testing)
- Data migrations (avoid triggering side effects)
- Bulk operations (publish a summary event instead)
