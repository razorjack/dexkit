# dexkit

Typed patterns for Rails, crafted for DX. Equip to gain +4 DEX.

**[Documentation](https://dex.razorjack.net)** · **[Design Philosophy](https://dex.razorjack.net/guide/philosophy)** · **[DX Meets AI](https://dex.razorjack.net/guide/ai)**

> **Pre-1.0.** Active development. The public API may change between minor versions.

Four base classes with contracts that enforce themselves:

- **[Dex::Operation](https://dex.razorjack.net/operation/)** – typed service objects with structured errors, transactions, and async execution
- **[Dex::Event](https://dex.razorjack.net/event/)** – immutable domain events with pub/sub, async handlers, and causality tracing
- **[Dex::Query](https://dex.razorjack.net/query/)** – declarative filters and sorts for ActiveRecord and Mongoid scopes
- **[Dex::Form](https://dex.razorjack.net/form/)** – form objects with typed fields, nested forms, and Rails form builder compatibility

## Operations

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

order = Order::Place.call(customer: 42, product: 7, quantity: 2)
```

Here's what you got:

- **`_Ref(Customer)`** accepts a Customer instance or an ID – the record is auto-fetched
- **`_Integer(1..)`** guarantees a positive integer before `perform` runs
- **`prop?`** marks optional inputs (nil by default)
- **`success` / `error`** declare the contract – typos in error codes raise `ArgumentError`
- **`error!`** halts execution, rolls back the transaction, returns a structured error
- **`after_commit`** fires only after the transaction succeeds – safe for emails, webhooks, events

### Pattern matching

`.safe.call` returns `Ok` or `Err` instead of raising:

```ruby
case Order::Place.new(customer: 42, product: 7, quantity: 2).safe.call
in Ok => result
  redirect_to order_path(result.id)
in Err(code: :out_of_stock)
  flash[:error] = "Product is out of stock"
  render :new
end
```

### Guards

Inline precondition checks with introspection — ask "can this run?" from views and controllers:

```ruby
guard :active_customer, "Customer account must be active" do
  !customer.suspended?
end

Order::Place.callable?(customer: customer, product: product, quantity: 1)
# => true / false
```

### Prescriptive errors

Every mistake tells you what went wrong, why, and what to do instead:

```ruby
error!(:not_found)
# => ArgumentError: Order::Place declares unknown error code :not_found.
#    Declared codes: [:out_of_stock]

prop :email, 123
# => Literal::TypeError: expected a type, got 123 (Integer)

once :nonexistent_prop
# => ArgumentError: Order::Place.once references unknown prop :nonexistent_prop.
#    Declared props: [:customer, :product, :quantity, :note]
```

### And more

[Ambient context](https://dex.razorjack.net/operation/context), [unified tracing](https://dex.razorjack.net/operation/tracing) with Stripe-style IDs, [idempotency](https://dex.razorjack.net/operation/once), [async execution](https://dex.razorjack.net/operation/async), [advisory locks](https://dex.razorjack.net/operation/advisory-lock), [DB recording](https://dex.razorjack.net/operation/recording), [explain](https://dex.razorjack.net/operation/explain) for preflight checks, [callbacks](https://dex.razorjack.net/operation/callbacks), a [customizable pipeline](https://dex.razorjack.net/operation/pipeline), [registry & export](https://dex.razorjack.net/tooling/registry), and [LLM tool integration](https://dex.razorjack.net/operation/llm-tools).

## Events

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

## Queries

```ruby
class Order::Query < Dex::Query
  scope { Order.all }

  prop? :status, String
  prop? :total_min, Integer

  filter :status
  filter :total_min, :gte, column: :total

  sort :created_at, :total, default: "-created_at"
end

Order::Query.call(status: "pending", sort: "-total")
```

## Forms

```ruby
class Order::Form < Dex::Form
  field :customer_email, :string
  field? :note, :string

  nested_many :line_items do
    field :product_id, :integer
    field :quantity, :integer, default: 1
  end
end
```

## Testing

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

## Installation

```ruby
gem "dexkit"
```

```bash
rake dex:guides  # install LLM-optimized guides as AGENTS.md in your app directories
```

## License

MIT
