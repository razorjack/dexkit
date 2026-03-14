---
description: "The design principles behind dexkit — why it favors explicit declarations, typed contracts, and prescriptive errors over convention and magic."
---

# Design Philosophy

dexkit makes a bet: Rails patterns should be explicit, typed, and mechanically enforced. Not documented in a wiki. Not agreed on in a PR review. Declared in code and validated at runtime.

## Start with just Ruby

A dexkit operation is a Ruby class with typed inputs and a `perform` method. That's the entire contract.

```ruby
class Order::Place < Dex::Operation
  prop :customer_id, Integer
  prop :product_id, Integer

  def perform
    Order.create!(customer_id: customer_id, product_id: product_id)
  end
end

Order::Place.call(customer_id: 42, product_id: 7)
```

No step DSL. No `call` chains. No result objects you're forced to unwrap. Write whatever Ruby you want inside `perform` – dexkit doesn't care. It owns the mechanics around your code (transactions, tracing, error handling), not the code itself.

When you're ready, capabilities layer on without changing the shape:

```ruby
class Order::Place < Dex::Operation
  description "Place a new order for a customer"

  prop :customer, _Ref(Customer)
  prop :product, _Ref(Product)
  prop :quantity, _Integer(1..)

  context customer: :current_customer
  success _Ref(Order)
  error :out_of_stock
  once :customer, :product

  guard :active_customer, "Customer account must be active" do
    !customer.suspended?
  end

  def perform
    error!(:out_of_stock) unless product.in_stock?
    Order.create!(customer: customer, product: product, quantity: quantity)
  end
end
```

Same class, same `perform`. The declarations above it are all opt-in – each one unlocks a capability without imposing structure on your business logic.

## Declare intent, enforce mechanically

When you do declare something, the framework holds you to it. Contracts are declared at the class level and enforced at runtime.

```ruby
error :out_of_stock
error :payment_failed

def perform
  error!(:not_found)  # undeclared code
end
```

```
ArgumentError: Order::Place declares unknown error code :not_found.
Declared codes: [:out_of_stock, :payment_failed]
```

No silent failures. No wrong error code slipping through to production. The declaration *is* the contract, and the framework enforces it.

## Prescriptive errors

Every error tells you what you did, why it's wrong, and what to do instead.

```ruby
prop :email, 123
# → Literal::TypeError: expected a type, got 123 (Integer)

async :carrier_pigeon
# → ArgumentError: unknown async adapter :carrier_pigeon.
#   Known adapters: [:active_job]

once :nonexistent_prop
# → ArgumentError: Order::Place.once references unknown prop :nonexistent_prop.
#   Declared props: [:customer, :product, :quantity, :note]
```

When something breaks, the error message is the documentation. This matters for developers debugging at 2am – and it matters equally for [coding agents](/guide/ai) that need to self-correct without another round-trip.

## One vocabulary across four patterns

Operation, Event, Query, and Form are independent – use one or all four – but they share the same concepts. `prop` and `prop?` define typed inputs on Operations, Events, and Queries. `field` and `field?` do the same for Forms, adapted to ActiveModel's type system. `description` and `desc:` document classes and individual fields everywhere. `context` maps inputs to ambient state – set `current_user` once in a controller and it flows into any pattern that declares it. Every pattern has a `.registry` that tracks named subclasses and exports its schema via `to_h` and `to_json_schema`.

Learn one of these concepts in any pattern, and you already know it in the others.

## Batteries included, opt-out possible

Sensible defaults that work without configuration. Every default is overridable.

Transactions wrap your operations automatically – `transaction false` to disable. Tracing assigns IDs and builds a call stack with no setup. Recording persists operation runs if you configure a record class, and stays invisible if you don't. Advisory locking, idempotency, async execution – they layer on when you need them and don't exist when you don't.

No setup ceremony, no feature flags, no configuration objects. Declare what you want and it works.
