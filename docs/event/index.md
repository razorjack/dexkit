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
- **Auto metadata** — prefixed `ev_...` IDs, UTC `timestamp`, `trace_id`, `event_ancestry`
- **Async by default** — handlers dispatched via ActiveJob
- **Causality tracing** — events share `trace_id` with the execution trace; explicit `caused_by:` links parent-child events
- **Suppression** — block-scoped silencing for tests and migrations
- **Ambient context** — auto-fill props from `Dex.with_context`, captured at publish time
- **Optional persistence** — store events to DB when configured
- **Test helpers** — event capturing, assertions, trace verification

## Description

Add a human-readable description to events, and `desc:` to individual props:

```ruby
class Order::Placed < Dex::Event
  description "Fired when an order is successfully placed"

  prop :order_id, Integer, desc: "The placed order's ID"
  prop :total, BigDecimal, desc: "Order total in base currency"
  prop? :coupon_code, String, desc: "Applied coupon code, if any"
end
```

Descriptions flow into export methods and JSON Schema output.

## Registry

All named Event subclasses are tracked automatically:

```ruby
Dex::Event.registry
# => #<Set: {Order::Placed, Order::Cancelled, ...}>

Dex::Event::Handler.registry
# => #<Set: {NotifyWarehouse, SendConfirmation, ...}>
```

See [Registry & Export](/tooling/registry) for details on deregistering, Zeitwerk compatibility, and the `dex:export` rake task.

## Export

Events support `to_h` and `to_json_schema` at the class level:

```ruby
Order::Placed.to_h
# => {
#   name: "Order::Placed",
#   description: "Fired when an order is successfully placed",
#   props: {
#     order_id: { type: "Integer", required: true, desc: "The placed order's ID" },
#     total:    { type: "BigDecimal", required: true, desc: "Order total in base currency" },
#     coupon_code: { type: "Nilable(String)", required: false, desc: "Applied coupon code, if any" }
#   }
# }

Order::Placed.to_json_schema
# => { "$schema": "https://json-schema.org/draft/2020-12/schema", type: "object", title: "Order::Placed", ... }
```

Bulk export across all registered events:

```ruby
Dex::Event.export(format: :hash)
Dex::Event.export(format: :json_schema)
```

Handlers also support `to_h` and bulk export:

```ruby
NotifyWarehouse.to_h
# => { name: "NotifyWarehouse", events: ["Order::Placed"], retries: 3, transaction: false, pipeline: [...] }

Dex::Event::Handler.export(format: :hash)
```

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
end
```
