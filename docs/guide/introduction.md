---
description: "Get started with dexkit's core building blocks for Rails – operations, events, forms, and queries – with examples and integration patterns."
---

# Introduction

dexkit is a Ruby library that gives you base classes for common Rails patterns. Equip to gain +4 DEX.

Four building blocks, each independent – use one or all:

- **[Dex::Operation](/operation/)** – service objects with typed properties, structured errors, transactions, callbacks, async execution, and more
- **[Dex::Event](/event/)** – typed immutable event objects with pub/sub, async dispatch, causality tracing, and optional persistence
- **[Dex::Form](/form/)** – form objects with typed attributes, normalization, validation, nested forms, and Rails form builder compatibility
- **[Dex::Query](/query/)** – query objects with declarative filters, sorting, type coercion from params, and Rails form binding

## A quick taste

An e-commerce order flow – from operation to event to form to query.

### Operations

```ruby
class Order::Place < Dex::Operation
  prop :customer, _Ref(Customer)
  prop :product, _Ref(Product)
  prop :quantity, _Integer(1..)
  prop? :note, String

  success _Ref(Order)
  error :out_of_stock

  def perform
    error!(:out_of_stock) unless product.in_stock?

    order = Order.create!(customer: customer, product: product, quantity: quantity, note: note)

    after_commit { Order::Placed.publish(order_id: order.id, total: order.total) }

    order
  end
end
```

That's one class. Here's what you got:

- **`_Ref(Customer)`** accepts a Customer instance or an ID – the record is auto-fetched
- **`_Integer(1..)`** guarantees a positive integer before `perform` runs
- **`prop?`** marks optional inputs (nil by default)
- **`success` / `error`** declare the contract – typos in error codes raise `ArgumentError`
- **`error!`** halts execution, rolls back the transaction, returns a structured error
- **`after_commit`** fires only after the transaction succeeds – safe for emails, webhooks, events

Call it:

```ruby
order = Order::Place.call(customer: 42, product: 7, quantity: 2)
```

`_Ref` props accept IDs – `customer: 42` finds `Customer.find(42)` automatically.

Handle outcomes with pattern matching:

```ruby
case Order::Place.new(customer: 42, product: 7, quantity: 2).safe.call
in Ok => result
  redirect_to order_path(result.id)
in Err(code: :out_of_stock)
  flash[:error] = "Product is out of stock"
  render :new
end
```

And there's more – [ambient context](/operation/context) for auto-filling `current_user` and friends, [guards](/operation/guards) for precondition checks, [async execution](/operation/async) via ActiveJob, [idempotency](/operation/once) with `once`, [advisory locks](/operation/advisory-lock), [DB recording](/operation/recording), [`rescue_from`](/operation/errors#rescue_from) for third-party exceptions, [callbacks](/operation/callbacks), a [customizable pipeline](/operation/pipeline), [registry & export](/tooling/registry) for contract introspection and JSON Schema generation, and [LLM tool integration](/operation/llm-tools) via ruby-llm.

### Events

Publish domain events, handle them sync or async:

```ruby
class Order::Placed < Dex::Event
  prop :order_id, Integer
  prop :total, BigDecimal
end

class NotifyWarehouse < Dex::Event::Handler
  on Order::Placed
  retries 3

  def perform
    WarehouseApi.reserve(event.order_id)
  end
end

Order::Placed.publish(order_id: 1, total: 99.99)
```

Handlers run via ActiveJob by default. Retries use exponential backoff. Events carry [causality tracing](/event/tracing) – link them in chains with shared trace IDs.

### Forms

User-facing input handling with nested forms and Rails integration:

```ruby
class Order::Form < Dex::Form
  attribute :note, :string

  nested_many :line_items do
    attribute :product_id, :integer
    attribute :quantity, :integer, default: 1
    validates :product_id, :quantity, presence: true
  end
end

form = Order::Form.new(params.require(:order))
```

Type casting, validation, `_destroy` support, and `form_with` / `fields_for` compatibility – no `accepts_nested_attributes_for` needed.

### Queries

Declarative filtering and sorting for ActiveRecord (and Mongoid) scopes:

```ruby
class Order::Query < Dex::Query
  scope { Order.all }

  prop? :status, String
  prop? :total_min, Integer

  filter :status
  filter :total_min, :gte, column: :total

  sort :created_at, :total, default: "-created_at"
end

orders = Order::Query.call(status: "pending", sort: "-total")
```

### Testing

First-class test helpers keep tests short:

```ruby
class PlaceOrderTest < Minitest::Test
  testing Order::Place

  def test_places_order
    assert_operation(customer: customer.id, product: product.id, quantity: 2)
  end

  def test_rejects_out_of_stock
    assert_operation_error(:out_of_stock, customer: customer.id,
                           product: out_of_stock_product.id, quantity: 1)
  end
end
```

## Why

Rails apps accumulate the same patterns over and over – service objects, event systems, form objects – but everyone rolls their own. You end up with inconsistent interfaces, manual error handling, no type checking, and testing that's more boilerplate than assertion. dexkit gives you a solid foundation so you can focus on business logic.

## Supported ORMs

dexkit works with both **ActiveRecord** and **Mongoid**. Queries, recording, model references, events, and forms adapt to your ORM automatically. Transactions are ActiveRecord-only – in Mongoid-only apps, operations run without a transaction wrapper, and `after_commit` fires immediately after success. If you need Mongoid transactions, use `Mongoid.transaction` directly inside `perform`.

## Next steps

- [Installation](/guide/installation) – add the gem and configure your app
- [Operation Overview](/operation/) – typed service objects
- [Event Overview](/event/) – domain events and handlers
- [Form Overview](/form/) – form objects and nested forms
- [Query Overview](/query/) – declarative filtering and sorting
