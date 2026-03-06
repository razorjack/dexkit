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

## Callbacks

Handlers support the same `before`, `after`, and `around` callbacks as operations:

```ruby
class ProcessOrderPayment < Dex::Event::Handler
  on Order::Paid

  before :log_start
  after :log_end

  def perform
    PaymentGateway.charge(event.order_id, event.amount)
  end

  private

  def log_start = Rails.logger.info("Processing payment for order #{event.order_id}")
  def log_end = Rails.logger.info("Payment processed for order #{event.order_id}")
end
```

`around` callbacks receive a continuation:

```ruby
around ->(cont) {
  Instrumentation.measure("payment") { cont.call }
}
```

Callbacks are inherited – child handlers run parent callbacks first, then their own.

## Transactions

Handlers can opt into database transactions with the `transaction` DSL. Transactions are **disabled by default** on handlers (unlike operations where they're on by default).

```ruby
class FulfillOrder < Dex::Event::Handler
  on Order::Placed
  transaction

  def perform
    order = Order.find(event.order_id)
    order.update!(status: "fulfilled")
    Shipment.create!(order: order)

    after_commit { Shipment::Ship.new(order_id: order.id).async.call }
  end
end
```

`after_commit` defers the block until the transaction commits. If the handler raises an exception, the transaction rolls back and deferred blocks are discarded.

Without `transaction`, `after_commit` blocks still defer until the handler pipeline completes, then fire in order.

## Custom pipeline

Handlers have the same `use` DSL as operations for adding custom wrapper modules:

```ruby
class Monitored < Dex::Event::Handler
  use MetricsWrapper, as: :metrics

  def perform
    # wrapped by MetricsWrapper#_metrics_wrap
  end
end
```

The default handler pipeline is `[:transaction, :callback]`.

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
