---
description: Wire operation props to ambient context with Dex.with_context – auto-fill current_user, tenant, locale without passing them explicitly every time.
---

# Ambient Context

Some inputs are per-request ambient data – `current_user`, `current_tenant`, `locale` – that many operations need but shouldn't receive explicitly every time. The `context` DSL wires props to an ambient store so they auto-fill when not passed.

## Setting context

Set ambient context in a controller `around_action` or middleware:

```ruby
class ApplicationController < ActionController::Base
  around_action :set_dex_context

  private

  def set_dex_context(&block)
    Dex.with_context(current_customer: current_customer, locale: I18n.locale, &block)
  end
end
```

`Dex.with_context` uses fiber-local storage (Ruby 3.2+). Safe with Puma, Falcon, and Rails executor – no thread-local leakage.

## Declaring context on an operation

Props are declared normally. The `context` line maps prop names to ambient keys:

```ruby
class Order::Place < Dex::Operation
  prop :product, _Ref(Product)
  prop :customer, _Ref(Customer)

  context customer: :current_customer

  def perform
    Order.create!(product: product, customer: customer)
  end
end
```

Now `Order::Place.call(product: product)` auto-fills `customer` from `Dex.context[:current_customer]`.

### Identity shorthand

When the prop name matches the context key:

```ruby
prop :locale, Symbol
context :locale   # shorthand for locale: :locale
```

### Mixed forms

```ruby
context :locale, customer: :current_customer
```

### Multiple calls

Calls are additive:

```ruby
context :locale
context customer: :current_customer
```

## Resolution order

When an operation is instantiated, context-mapped props resolve in this order:

1. **Explicit kwarg** – `Order::Place.call(customer: admin)` always wins
2. **Ambient context** – `Dex.context[:current_customer]`
3. **Prop default** – if `prop?` or `default:`
4. **Nothing** – `Literal::TypeError` for required props

This makes tests trivial – just pass everything explicitly, no `Dex.with_context` needed:

```ruby
Order::Place.call(product: product, customer: customer)
```

## Optional props

```ruby
prop? :tenant, _Ref(Tenant)
context tenant: :current_tenant
```

If ambient context has `:current_tenant`, it fills in. If not, `tenant` is nil.

A context key present with an explicit `nil` value counts as "provided" and overrides prop defaults. If your middleware doesn't have a tenant, omit the key entirely rather than setting it to `nil`:

```ruby
ctx = { locale: I18n.locale }
ctx[:current_tenant] = current_tenant if current_tenant
Dex.with_context(**ctx) do
  # operations here
end
```

## Nesting

Inner blocks merge with the outer context and restore on exit:

```ruby
Dex.with_context(current_customer: admin, locale: :en) do
  Dex.with_context(locale: :fr) do
    # context: { current_customer: admin, locale: :fr }
  end
  # context: { current_customer: admin, locale: :en }
end
```

In practice, nesting is rarely needed. Set context once in the controller, pass explicit kwargs for one-off overrides.

## Nested operations

Operations called inside another operation inherit the same ambient context:

```ruby
class Order::PlaceAndNotify < Dex::Operation
  prop :product, _Ref(Product)
  prop :customer, _Ref(Customer)
  context customer: :current_customer

  def perform
    order = Order::Place.call(product: product)   # inherits current_customer
    Notification::Send.call(order: order)          # same
    order
  end
end
```

## Guards

Guards have access to context-resolved props – they're just regular instance methods:

```ruby
class Order::Place < Dex::Operation
  prop :product, _Ref(Product)
  prop :customer, _Ref(Customer)
  context customer: :current_customer

  guard :suspended, "Suspended customers cannot place orders" do
    customer.suspended?
  end

  def perform
    Order.create!(product: product, customer: customer)
  end
end
```

Introspection with ambient context:

```ruby
Dex.with_context(current_customer: customer) do
  Order::Place.callable?(product: product)
end

# Or pass explicitly:
Order::Place.callable?(product: product, customer: admin)
```

## Events

Events use the same `context` DSL. Context-mapped props are captured at **publish time** and stored as regular typed props on the event. Handlers don't need ambient context – they read from the event:

```ruby
class Order::Placed < Dex::Event
  prop :order_id, Integer
  prop :customer, _Ref(Customer)
  context customer: :current_customer
end

Dex.with_context(current_customer: customer) do
  Order::Placed.publish(order_id: 1)   # customer captured from context
end
```

See [Event Publishing](/event/publishing) for more.

## Introspection

```ruby
Order::Place.context_mappings
# => { customer: :current_customer }
```

## Inheritance

Child classes inherit parent context mappings and can add their own:

```ruby
class BaseOperation < Dex::Operation
  prop :customer, _Ref(Customer)
  context customer: :current_customer
end

class Order::Place < BaseOperation
  prop :locale, Symbol
  context :locale   # adds to parent's mappings
end

Order::Place.context_mappings
# => { customer: :current_customer, locale: :locale }
```
