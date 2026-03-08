# Dex::Event — LLM Reference

Copy this to your app's event handlers directory (e.g., `app/event_handlers/AGENTS.md`) so coding agents know the full API when implementing and testing events.

---

## Reference Event

All examples below build on this event unless noted otherwise:

```ruby
class OrderPlaced < Dex::Event
  prop :order_id, Integer
  prop :total, BigDecimal
  prop? :coupon_code, String
end
```

---

## Defining Events

Typed, immutable value objects. Props defined with `prop` (required) and `prop?` (optional). Same type system as `Dex::Operation`.

```ruby
class UserCreated < Dex::Event
  prop :user_id, Integer
  prop :email, String
  prop? :referrer, String
end
```

Reserved names: `id`, `timestamp`, `trace_id`, `caused_by_id`, `caused_by`, `context`, `publish`, `metadata`, `sync`.

Events are frozen after creation. Each gets auto-generated `id` (UUID), `timestamp` (UTC), `trace_id`, and optional `caused_by_id`.

### Literal Types Cheatsheet

Same types as Operation — `String`, `Integer`, `_Integer(1..)`, `_Array(String)`, `_Union("a", "b")`, `_Nilable(String)`, `_Ref(Model)`, etc.

---

## Publishing

```ruby
# Class-level (most common)
OrderPlaced.publish(order_id: 1, total: 99.99)              # async (default)
OrderPlaced.publish(order_id: 1, total: 99.99, sync: true)   # sync

# Instance-level
event = OrderPlaced.new(order_id: 1, total: 99.99)
event.publish                    # async
event.publish(sync: true)        # sync

# With causality
OrderPlaced.publish(order_id: 1, total: 99.99, caused_by: parent_event)
```

**Async** (default): handlers dispatched via ActiveJob. **Sync**: handlers called inline.

---

## Handling

Handlers are classes that subscribe to events. Subscription is automatic via `on`:

```ruby
class NotifyWarehouse < Dex::Event::Handler
  on OrderPlaced
  on OrderUpdated            # subscribe to multiple events

  def perform
    event                    # accessor — the event instance
    event.order_id           # typed props
    event.id                 # UUID
    event.timestamp          # Time (UTC)
    event.caused_by_id       # parent event ID (if traced)
    event.trace_id           # shared trace ID across causal chain
  end
end
```

**Multi-event handlers**: A single handler can subscribe to multiple event types.

### Loading Handlers (Rails)

Handlers must be loaded for `on` to register. Standard pattern:

```ruby
# config/initializers/events.rb
Rails.application.config.to_prepare do
  Dex::Event::Bus.clear!
  Dir.glob(Rails.root.join("app/event_handlers/**/*.rb")).each { |e| require(e) }
end
```

### Retries

```ruby
class ProcessPayment < Dex::Event::Handler
  on PaymentReceived
  retries 3                              # exponential backoff (1s, 2s, 4s)
  retries 3, wait: 10                    # fixed 10s between retries
  retries 3, wait: ->(attempt) { attempt * 5 }  # custom delay

  def perform
    # ...
  end
end
```

When retries exhausted, exception propagates normally.

### Callbacks

Same `before`/`after`/`around` DSL as operations:

```ruby
class ProcessPayment < Dex::Event::Handler
  on PaymentReceived

  before :log_start
  after :log_end

  around ->(cont) {
    Instrumentation.measure("payment") { cont.call }
  }

  def perform
    PaymentGateway.charge(event.amount)
  end

  private

  def log_start = Rails.logger.info("Processing payment...")
  def log_end = Rails.logger.info("Payment processed")
end
```

Callbacks are inherited. Child handlers run parent callbacks first.

### Transactions

Handlers can opt into database transactions and deferred `after_commit`:

```ruby
class FulfillOrder < Dex::Event::Handler
  on OrderPlaced
  transaction

  def perform
    order = Order.find(event.order_id)
    order.update!(status: "fulfilled")

    after_commit { Shipment::Ship.new(order_id: order.id).async.call }
  end
end
```

Transactions are **disabled by default** on handlers (unlike operations). Opt in with `transaction`. The `after_commit` block defers until the transaction commits; on exception, deferred blocks are discarded.

### Custom Pipeline

Handlers support the same `use` DSL as operations for adding custom wrappers:

```ruby
class Monitored < Dex::Event::Handler
  use MetricsWrapper, as: :metrics

  def perform
    # ...
  end
end
```

Default handler pipeline: `[:transaction, :callback]`.

---

## Tracing (Causality)

Link events in a causal chain. All events in a chain share the same `trace_id`.

```ruby
order_placed = OrderPlaced.new(order_id: 1, total: 99.99)

# Option 1: trace block
order_placed.trace do
  InventoryReserved.publish(order_id: 1)   # caused_by_id = order_placed.id
  ShippingRequested.publish(order_id: 1)   # same trace_id
end

# Option 2: caused_by keyword
InventoryReserved.publish(order_id: 1, caused_by: order_placed)
```

Nesting works — each child gets the nearest parent's `id` as `caused_by_id`, and the root's `trace_id`.

---

## Suppression

Prevent events from being published (useful in tests, migrations, bulk ops):

```ruby
Dex::Event.suppress { ... }                         # suppress all events
Dex::Event.suppress(OrderPlaced) { ... }             # suppress specific class
Dex::Event.suppress(OrderPlaced, UserCreated) { ... } # suppress multiple
```

Suppression is block-scoped and nestable. Child classes are suppressed when parent is.

---

## Persistence (Optional)

Store events to database when configured:

```ruby
Dex.configure do |c|
  c.event_store = EventRecord   # any model with create!(event_type:, payload:, metadata:)
end
```

```ruby
create_table :event_records do |t|
  t.string :event_type
  t.jsonb  :payload
  t.jsonb  :metadata
  t.timestamps
end
```

Persistence failures are silently rescued — they never halt event publishing.

---

## Ambient Context

Events use the same `context` DSL as operations. Context-mapped props are captured at **publish time** and stored as regular props on the event — handlers don't need ambient context, they read from the event.

```ruby
class Order::Placed < Dex::Event
  prop :order_id, Integer
  prop :customer, _Ref(Customer)
  context customer: :current_customer   # resolved at publish time
end

# In a controller with Dex.with_context(current_customer: customer):
Order::Placed.publish(order_id: 1)   # customer auto-filled from context

# Or pass explicitly:
Order::Placed.publish(order_id: 1, customer: customer)
```

Handlers receive the event with everything already set — no `context` needed on handlers:

```ruby
class AuditTrail < Dex::Event::Handler
  on Order::Placed

  def perform
    AuditLog.create!(customer: event.customer, action: "placed", order_id: event.order_id)
  end
end
```

**Resolution order:** explicit kwarg → ambient context → prop default → TypeError.

**Introspection:** `MyEvent.context_mappings` returns the mapping hash.

### Legacy Context (Metadata)

The older `event_context` / `restore_event_context` configuration captures arbitrary metadata at publish time and restores it before async handler execution. Both mechanisms coexist.

---

## Configuration

```ruby
# config/initializers/dexkit.rb
Dex.configure do |config|
  config.event_store = nil               # model for persistence (default: nil)
  config.event_context = nil             # -> { Hash } lambda (default: nil)
  config.restore_event_context = nil     # ->(ctx) { ... } lambda (default: nil)
end
```

Everything works without configuration. All three settings are optional.

---

## Testing

```ruby
# test/test_helper.rb
require "dex/event_test_helpers"

class Minitest::Test
  include Dex::Event::TestHelpers
end
```

Not autoloaded — stays out of production.

### Capturing Events

Captures events instead of dispatching handlers:

```ruby
def test_publishes_order_placed
  capture_events do
    OrderPlaced.publish(order_id: 1, total: 99.99)

    assert_event_published(OrderPlaced)
    assert_event_published(OrderPlaced, order_id: 1)
    assert_event_count(OrderPlaced, 1)
    refute_event_published(OrderCancelled)
  end
end
```

Outside `capture_events`, events are dispatched synchronously (test safety).

### Assertions

```ruby
# Published
assert_event_published(EventClass)                    # any instance
assert_event_published(EventClass, prop: value)       # with prop match
refute_event_published                                # nothing published
refute_event_published(EventClass)                    # specific class not published

# Count
assert_event_count(EventClass, 3)

# Tracing
assert_event_trace(parent_event, child_event)         # caused_by_id match
assert_same_trace(event_a, event_b, event_c)          # shared trace_id
```

### Suppression in Tests

```ruby
def test_no_side_effects
  Dex::Event.suppress do
    CreateOrder.call(item_id: 1)  # events suppressed
  end
end
```

### Complete Test Example

```ruby
class CreateOrderTest < Minitest::Test
  include Dex::Event::TestHelpers

  def test_publishes_order_placed
    capture_events do
      order = CreateOrder.call(item_id: 1, quantity: 2)

      assert_event_published(OrderPlaced, order_id: order.id)
      assert_event_count(OrderPlaced, 1)
      refute_event_published(OrderCancelled)
    end
  end

  def test_trace_chain
    capture_events do
      parent = OrderPlaced.new(order_id: 1, total: 99.99)

      parent.trace do
        InventoryReserved.publish(order_id: 1)
      end

      child = _dex_published_events.last
      assert_event_trace(parent, child)
      assert_same_trace(parent, child)
    end
  end
end
```

---

## Registry, Export & Description

### Description

Events can declare a human-readable description. Props can include `desc:`:

```ruby
class Order::Placed < Dex::Event
  description "Emitted after an order is successfully placed"

  prop :order_id, Integer, desc: "The placed order"
  prop :total, BigDecimal, desc: "Order total"
end
```

### Registry

```ruby
Dex::Event.registry            # => #<Set: {Order::Placed, Order::Cancelled, ...}>
Dex::Event::Handler.registry   # => #<Set: {NotifyWarehouse, SendConfirmation, ...}>
Dex::Event.deregister(klass)
Dex::Event::Handler.deregister(klass)
```

### Export

```ruby
Order::Placed.to_h
# => { name: "Order::Placed", description: "...", props: { order_id: { type: "Integer", ... } } }

Order::Placed.to_json_schema   # JSON Schema (Draft 2020-12)

NotifyWarehouse.to_h
# => { name: "NotifyWarehouse", events: ["Order::Placed"], retries: 3, ... }

Dex::Event.export                         # all events as hashes
Dex::Event.export(format: :json_schema)   # all as JSON Schema
Dex::Event::Handler.export                # all handlers as hashes
```

---

**End of reference.**
