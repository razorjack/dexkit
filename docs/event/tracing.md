---
description: Trace event causality with trace_id and caused_by, and suppress event publication selectively with Dex::Event tools.
---

# Tracing & Suppression

## Causality tracing

Every event gets a `trace_id`. When events are linked via tracing, they share the same `trace_id`, forming a causal chain.

### Using trace blocks

```ruby
order_placed = Order::Placed.new(order_id: 1, total: 99.99)

order_placed.trace do
  Shipment::Reserved.publish(order_id: 1)
  # caused_by_id = order_placed.id
  # trace_id = order_placed.trace_id
end
```

### Using caused_by

```ruby
Shipment::Reserved.publish(order_id: 1, caused_by: order_placed)
```

### Nested tracing

```ruby
order_placed.trace do
  reserved = Shipment::Reserved.new(order_id: 1)
  reserved.trace do
    Shipment::Requested.publish(order_id: 1)
    # caused_by_id = reserved.id
    # trace_id = order_placed.trace_id (inherited from root)
  end
end
```

### Metadata

Every event includes:

| Field | Description |
|---|---|
| `id` | Unique UUID |
| `timestamp` | UTC time of creation |
| `trace_id` | Shared across causal chain (defaults to `id` for root events) |
| `caused_by_id` | Parent event's `id` (nil for root events) |
| `context` | Ambient context hash (from config) |

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
  Order::PriorityPlaced.publish(...)  # also suppressed
end
```

Suppression is commonly used in:
- Tests (isolate what you're testing)
- Data migrations (avoid triggering side effects)
- Bulk operations (publish a summary event instead)
