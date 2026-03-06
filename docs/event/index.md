---
description: Define typed immutable events with Dex::Event and connect them to handlers, async dispatch, tracing, suppression, and persistence.
---

# Dex::Event

Typed, immutable event value objects with publish/subscribe, async handler dispatch, causality tracing, suppression, and optional persistence.

## Quick Start

### 1. Define an event

```ruby
class Order::Placed < Dex::Event
  prop :order_id, Integer
  prop :total, BigDecimal
  prop? :coupon_code, String
end
```

### 2. Define a handler

```ruby
class NotifyWarehouse < Dex::Event::Handler
  on Order::Placed

  def perform
    WarehouseApi.notify(event.order_id)
  end
end
```

### 3. Publish

```ruby
Order::Placed.publish(order_id: 1, total: 99.99)
```

## What you get

- **Typed properties** — same `prop` / `prop?` system as `Dex::Operation`
- **Immutability** — events are frozen on creation
- **Auto metadata** — UUID `id`, UTC `timestamp`, `trace_id`
- **Async by default** — handlers dispatched via ActiveJob
- **Causality tracing** — link events in chains with shared `trace_id`
- **Suppression** — block-scoped silencing for tests and migrations
- **Optional persistence** — store events to DB when configured
- **Test helpers** — event capturing, assertions, trace verification

## Zero-config

Everything works without configuration. Define events, define handlers, publish. Persistence and context capture are opt-in.

## Loading handlers in Rails

Handlers must be loaded so `on` can register subscriptions. With Zeitwerk, add an initializer:

```ruby
# config/initializers/events.rb
Rails.application.config.to_prepare do
  Dex::Event::Bus.clear!
  Dir.glob(Rails.root.join("app/event_handlers/**/*.rb")).each { |e| require(e) }
end
```

## Configuration

All optional:

```ruby
Dex.configure do |config|
  config.event_store = EventRecord              # persist events to DB
  config.event_context = -> { { user_id: Current.user&.id } }
  config.restore_event_context = ->(ctx) { Current.user = User.find(ctx["user_id"]) }
end
```
