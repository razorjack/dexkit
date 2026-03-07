---
description: Make Dex::Operation calls idempotent with the once DSL – duplicate calls replay stored results instead of re-executing.
---

# Idempotency

Make operations idempotent with `once`. The first call executes normally; subsequent calls with the same key replay the stored result without re-executing `perform`.

Both successful results and business errors are replayed. Unhandled exceptions release the key so the operation can be retried.

## Setup

`once` builds on top of [Recording](/operation/recording) – it needs the record backend to store and look up idempotency keys. Add two columns to your record table:

```ruby
# migration
add_column :operation_records, :once_key, :string
add_column :operation_records, :once_key_expires_at, :datetime
add_index :operation_records, :once_key, unique: true
```

The unique index is critical – it prevents race conditions where two concurrent calls both try to claim the same key.

## Basic usage

```ruby
class Order::Place < Dex::Operation
  prop :order_id, Integer
  once :order_id

  def perform
    Order.find(order_id).charge!
  end
end

Order::Place.call(order_id: 42)   # executes perform
Order::Place.call(order_id: 42)   # replays stored result
Order::Place.call(order_id: 99)   # different key – executes perform
```

The idempotency key is derived from the operation class name and the specified prop values. In this example, `Order::Place/order_id=42`.

## Key forms

### Named props

Specify which props form the idempotency key:

```ruby
class Shipment::Ship < Dex::Operation
  prop :order_id, Integer
  prop :warehouse_id, Integer
  prop? :note, String

  once :order_id, :warehouse_id
  # key: "Shipment::Ship/order_id=1/warehouse_id=5"
end
```

Only the listed props contribute to the key. Other props (like `note` above) can vary between calls without affecting idempotency.

### All props

Bare `once` uses every prop:

```ruby
class Product::Import < Dex::Operation
  prop :source, String
  prop :external_id, String
  once
  # key: "Product::Import/external_id=abc/source=csv"
end
```

### Block

A block gives full control over the key string:

```ruby
class Order::Charge < Dex::Operation
  prop :order_id, Integer
  prop :attempt, Integer

  once { "charge-#{order_id}" }
  # key: "charge-42" (ignores attempt)
end
```

The block runs in the operation instance context, so all props are accessible.

### Instance-level key

Set the key at the call site instead of (or overriding) the class-level declaration:

```ruby
# Use a key from an external system
Order::Place.new(order_id: 42).once("webhook-evt-abc123").call

# Works even without a class-level `once` declaration
Order::Refund.new(order_id: 42).once("refund-#{idempotency_token}").call
```

Pass `nil` to bypass idempotency for a specific call:

```ruby
Order::Place.new(order_id: 42).once(nil).call  # always executes
```

## Expiry

Keys live forever by default. Set `expires_in` to make them expire:

```ruby
class Customer::SendDigest < Dex::Operation
  prop :customer_id, Integer
  once :customer_id, expires_in: 24.hours

  def perform
    DigestMailer.daily(customer_id).deliver_now
  end
end

Customer::SendDigest.call(customer_id: 1)   # sends email
Customer::SendDigest.call(customer_id: 1)   # replayed (within 24 hours)
# ... 24 hours later ...
Customer::SendDigest.call(customer_id: 1)   # sends email again
```

## What gets replayed

**Successful results** are stored and returned on replay, preserving typed values when `success` is declared:

```ruby
class Order::Total < Dex::Operation
  prop :order_id, Integer
  success BigDecimal
  once :order_id

  def perform
    BigDecimal("99.99")
  end
end

Order::Total.call(order_id: 1)  # => BigDecimal("99.99")
Order::Total.call(order_id: 1)  # => BigDecimal("99.99") (replayed, same type)
```

**Business errors** (via `error!`) are also replayed – the same `Dex::Error` is raised:

```ruby
class Order::Place < Dex::Operation
  prop :order_id, Integer
  error :out_of_stock
  once :order_id

  def perform
    error!(:out_of_stock, "No inventory")
  end
end

Order::Place.call(order_id: 1)  # raises Dex::Error(:out_of_stock)
Order::Place.call(order_id: 1)  # raises Dex::Error(:out_of_stock) (replayed)
```

**Unhandled exceptions** do not consume the key. The record is marked as `failed` and the key is released, so the operation can be retried:

```ruby
Order::Place.call(order_id: 1)   # raises RuntimeError, key released
Order::Place.call(order_id: 1)   # executes again (not a replay)
```

This is intentional – exceptions represent transient failures (network timeouts, database errors) that should be retryable, while business errors represent permanent decisions that should be consistent.

## Clearing keys

Use `clear_once!` to release a consumed key, allowing re-execution:

```ruby
# Clear by prop values (matches the class-level `once` declaration)
Order::Place.clear_once!(order_id: 42)

# Clear by string key (for instance-level keys)
Order::Place.clear_once!("webhook-evt-abc123")

# Then call again – executes perform
Order::Place.call(order_id: 42)
```

Clearing a non-existent key is a no-op.

## Safe mode

`once` works with `.safe` – replayed results are wrapped in `Ok`/`Err` as expected:

```ruby
case Order::Place.new(order_id: 42).safe.call
in Ok => result
  # first call or replayed success
in Err(code: :out_of_stock)
  # first call or replayed error
end
```

## Pipeline position

`once` runs early in the pipeline, right after `result` and before `lock`:

```
result > once > lock > record > transaction > rescue > callbacks > perform
```

This means the idempotency check happens before acquiring locks or opening transactions – a replayed result returns immediately with minimal overhead.
