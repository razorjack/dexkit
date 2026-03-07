# dexkit

Rails patterns toolbelt. Equip to gain +4 DEX.

**[Documentation](https://dex.razorjack.net)**

## Operations

Service objects with typed properties, transactions, error handling, and more.

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
order.id  # => 1
```

### What you get out of the box

**Typed properties** – powered by [literal](https://github.com/joeldrapper/literal). Plain classes, ranges, unions, arrays, nilable, and model references with auto-find:

```ruby
prop :quantity, _Integer(1..)
prop :currency, _Union("USD", "EUR", "GBP")
prop :customer, _Ref(Customer)        # accepts Customer instance or ID
prop? :note, String                    # optional (nil by default)
```

**Structured errors** with `error!`, `assert!`, and `rescue_from`:

```ruby
product = assert!(:not_found) { Product.find_by(id: product_id) }

rescue_from Stripe::CardError, as: :payment_declined
```

**Ok / Err** – pattern match on operation outcomes with `.safe.call`:

```ruby
case Order::Place.new(customer: 42, product: 7, quantity: 2).safe.call
in Ok => result
  redirect_to order_path(result.id)
in Err(code: :out_of_stock)
  flash[:error] = "Product is out of stock"
end
```

**Async execution** via ActiveJob:

```ruby
Order::Fulfill.new(order_id: 123).async(queue: "fulfillment").call
```

**Idempotency** with `once` — run an operation at most once for a given key. Results are replayed on duplicates:

```ruby
class Payment::Charge < Dex::Operation
  prop :order_id, Integer
  prop :amount, Integer

  once :order_id                          # key from prop
  # once :order_id, :merchant_id          # composite key
  # once                                  # all props as key
  # once { "custom-#{order_id}" }         # block-based key
  # once :order_id, expires_in: 24.hours  # expiring key

  def perform
    Gateway.charge!(order_id, amount)
  end
end

# Call-site key (overrides class-level declaration)
Payment::Charge.new(order_id: 1, amount: 500).once("ext-key-123").call

# Bypass once guard for a single call
Payment::Charge.new(order_id: 1, amount: 500).once(nil).call

# Clear a stored key to allow re-execution
Payment::Charge.clear_once!(order_id: 1)
```

Business errors are replayed; exceptions release the key so the operation can be retried. Requires the record backend (recording is enabled by default when `record_class` is configured).

**Guards** – inline precondition checks with introspection. Ask "can this operation run?" from views and controllers:

```ruby
guard :out_of_stock, "Product must be in stock" do
  !product.in_stock?
end

# In a view or controller:
Order::Place.callable?(customer: customer, product: product, quantity: 1)
```

**Ambient context** – declare which props come from ambient state. Set once in a controller, auto-fill everywhere:

```ruby
class Order::Place < Dex::Operation
  prop :product, _Ref(Product)
  prop :customer, _Ref(Customer)
  context customer: :current_customer   # filled from Dex.context[:current_customer]

  def perform
    Order.create!(product: product, customer: customer)
  end
end

# Controller
Dex.with_context(current_customer: current_customer) do
  Order::Place.call(product: product)   # customer auto-filled
end

# Tests – just pass it explicitly
Order::Place.call(product: product, customer: customer)
```

**Transactions** on by default, **advisory locking**, **recording** to database, **callbacks**, and a customizable **pipeline** – all composable, all optional.

### Testing

First-class test helpers for Minitest:

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

## Events

Typed, immutable event objects with publish/subscribe, async dispatch, and causality tracing.

```ruby
class Order::Placed < Dex::Event
  prop :order_id, Integer
  prop :total, BigDecimal
  prop? :coupon_code, String
end

class NotifyWarehouse < Dex::Event::Handler
  on Order::Placed
  retries 3

  def perform
    WarehouseApi.notify(event.order_id)
  end
end

Order::Placed.publish(order_id: 1, total: 99.99)
```

### What you get out of the box

**Zero-config pub/sub** — define events and handlers, publish. No bus setup needed.

**Async by default** — handlers dispatched via ActiveJob. `sync: true` for inline.

**Causality tracing** — link events in chains with shared `trace_id`:

```ruby
order_placed.trace do
  Shipment::Reserved.publish(order_id: 1)
end
```

**Callbacks** — `before`, `after`, `around` hooks on handlers, same DSL as operations.

**Transactions** — opt-in `transaction` and `after_commit` for handlers that write to the database.

**Suppression**, optional **persistence**, **context capture**, and **retries** with exponential backoff.

### Testing

```ruby
class PlaceOrderTest < Minitest::Test
  include Dex::Event::TestHelpers

  def test_publishes_order_placed
    capture_events do
      Order::Place.call(customer: customer.id, product: product.id, quantity: 2)
      assert_event_published(Order::Placed)
    end
  end
end
```

## Forms

Form objects with typed attributes, normalization, nested forms, and Rails form builder compatibility.

```ruby
class Employee::Form < Dex::Form
  model Employee

  attribute :first_name, :string
  attribute :last_name, :string
  attribute :email, :string

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  validates :email, presence: true, uniqueness: true
  validates :first_name, :last_name, presence: true

  nested_one :address do
    attribute :street, :string
    attribute :city, :string
    validates :street, :city, presence: true
  end
end

form = Employee::Form.new(email: "  ALICE@EXAMPLE.COM  ", first_name: "Alice", last_name: "Smith")
form.email  # => "alice@example.com"
form.valid?
```

### What you get out of the box

**ActiveModel attributes** with type casting, normalization, and full Rails validation DSL.

**Nested forms** — `nested_one` and `nested_many` with automatic Hash coercion, `_destroy` support, and error propagation:

```ruby
nested_many :emergency_contacts do
  attribute :name, :string
  attribute :phone, :string
  validates :name, :phone, presence: true
end
```

**Rails form compatibility** — works with `form_with`, `fields_for`, and nested attributes out of the box.

**Uniqueness validation** against the database, with scope, case-sensitivity, and current-record exclusion.

**Multi-model forms** — when a form spans Employee, Department, and Address, define a `.for` convention method to map records and a `#save` method that delegates to a `Dex::Operation`:

```ruby
def save
  return false unless valid?

  case operation.safe.call
  in Ok then true
  in Err => e then errors.add(:base, e.message) and false
  end
end
```

## Queries

Declarative query objects for filtering and sorting ActiveRecord relations and Mongoid criteria.

```ruby
class Order::Query < Dex::Query
  scope { Order.all }

  prop? :status, String
  prop? :customer, _Ref(Customer)
  prop? :total_min, Integer

  filter :status
  filter :customer
  filter :total_min, :gte, column: :total

  sort :created_at, :total, default: "-created_at"
end

orders = Order::Query.call(status: "pending", sort: "-total")
```

### What you get out of the box

**11 built-in filter strategies** — `:eq`, `:not_eq`, `:contains`, `:starts_with`, `:ends_with`, `:gt`, `:gte`, `:lt`, `:lte`, `:in`, `:not_in`. Custom blocks for complex logic.

**Sorting** with ascending/descending column sorts, custom sort blocks, and defaults.

**`from_params`** — HTTP boundary handling with automatic coercion, blank stripping, and invalid value fallback:

```ruby
class OrdersController < ApplicationController
  def index
    query = Order::Query.from_params(params, scope: policy_scope(Order))
    @orders = pagy(query.resolve)
  end
end
```

**Form binding** — works with `form_with` for search forms. Queries respond to `model_name`, `param_key`, `persisted?`, and `to_params`.

**Scope injection** — narrow the base scope at call time without modifying the query class.

## Installation

```ruby
gem "dexkit"
```

## Documentation

Full documentation at **[dex.razorjack.net](https://dex.razorjack.net)**.

## AI Coding Assistant Setup

dexkit ships LLM-optimized guides. Copy them into your project so AI agents automatically know the API:

```bash
cp $(bundle show dexkit)/guides/llm/OPERATION.md app/operations/CLAUDE.md
cp $(bundle show dexkit)/guides/llm/EVENT.md app/event_handlers/CLAUDE.md
cp $(bundle show dexkit)/guides/llm/FORM.md app/forms/CLAUDE.md
cp $(bundle show dexkit)/guides/llm/QUERY.md app/queries/CLAUDE.md
```

## License

MIT
