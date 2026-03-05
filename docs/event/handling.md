# Handling Events

## Defining a handler

Subclass `Dex::Event::Handler` and implement `perform`:

```ruby
class NotifyWarehouse < Dex::Event::Handler
  on Order::Placed

  def perform
    WarehouseApi.notify(event.order_id)
  end
end
```

The `event` accessor gives you the published event instance with all typed props.

## Multi-event handlers

Subscribe to multiple events in one handler:

```ruby
class AuditLogger < Dex::Event::Handler
  on Order::Placed
  on Order::Cancelled
  on Order::Paid

  def perform
    AuditLog.create!(
      event_type: event.class.name,
      event_id: event.id,
      timestamp: event.timestamp
    )
  end
end
```

## Retries

Configure automatic retries for transient failures:

```ruby
class ProcessOrderPayment < Dex::Event::Handler
  on Order::Paid
  retries 3                                           # exponential backoff
  retries 3, wait: 10                                 # fixed 10s delay
  retries 3, wait: ->(attempt) { attempt * 5 }        # custom delay

  def perform
    PaymentGateway.process(event.order_id)
  end
end
```

| Wait option | Behavior |
|---|---|
| *(none)* | Exponential: 1s, 2s, 4s, ... |
| `wait: 10` | Fixed 10s between retries |
| `wait: ->(n) { n * 5 }` | Custom: 5s, 10s, 15s, ... |

When retries are exhausted, the exception propagates to the job framework.

## Loading handlers

Handlers must be loaded for `on` to register subscriptions. In Rails with Zeitwerk:

```ruby
# config/initializers/events.rb
Rails.application.config.to_prepare do
  Dex::Event::Bus.clear!
  Dir.glob(Rails.root.join("app/event_handlers/**/*.rb")).each { |e| require(e) }
end
```

## Manual subscription

You can also subscribe/unsubscribe programmatically:

```ruby
Dex::Event::Bus.subscribe(Order::Placed, NotifyWarehouse)
Dex::Event::Bus.unsubscribe(Order::Placed, NotifyWarehouse)
```

Subscriptions are idempotent — duplicate calls are harmless.
