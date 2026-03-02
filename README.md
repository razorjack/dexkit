# Dexkit

Rails patterns toolbelt. Equip to gain +4 DEX.

**[Documentation](https://dex.razorjack.net)**

## Operations

Service objects with typed properties, transactions, error handling, and more.

```ruby
class CreateUser < Dex::Operation
  prop :name,  String
  prop :email, String

  success _Ref(User)
  error   :email_taken

  def perform
    error!(:email_taken) if User.exists?(email: email)
    User.create!(name: name, email: email)
  end
end

user = CreateUser.call(name: "Alice", email: "alice@example.com")
user.name  # => "Alice"
```

### What you get out of the box

**Typed properties** – powered by [literal](https://github.com/joeldrapper/literal). Plain classes, ranges, unions, arrays, nilable, and model references with auto-find:

```ruby
prop :amount,   _Integer(1..)
prop :currency, _Union("USD", "EUR", "GBP")
prop :user,     _Ref(User)           # accepts User instance or ID
prop? :note,    String               # optional (nil by default)
```

**Structured errors** with `error!`, `assert!`, and `rescue_from`:

```ruby
user = assert!(:not_found) { User.find_by(id: user_id) }

rescue_from Stripe::CardError, as: :card_declined
```

**Ok / Err** – pattern match on operation outcomes with `.safe.call`:

```ruby
include Dex::Match

case CreateUser.new(email: email).safe.call
in Ok(name:)
  puts "Welcome, #{name}!"
in Err(code: :email_taken)
  puts "Already registered"
end
```

**Async execution** via ActiveJob:

```ruby
SendWelcomeEmail.new(user_id: 123).async(queue: "mailers").call
```

**Transactions** on by default, **advisory locking**, **recording** to database, **callbacks**, and a customizable **pipeline** – all composable, all optional.

### Testing

First-class test helpers for Minitest:

```ruby
class CreateUserTest < Minitest::Test
  testing CreateUser

  def test_creates_user
    assert_operation(name: "Alice", email: "alice@example.com")
  end

  def test_rejects_duplicate_email
    assert_operation_error(:email_taken, name: "Alice", email: "taken@example.com")
  end
end
```

## Events

Typed, immutable event objects with publish/subscribe, async dispatch, and causality tracing.

```ruby
class OrderPlaced < Dex::Event
  prop :order_id, Integer
  prop :total, BigDecimal
  prop? :coupon_code, String
end

class NotifyWarehouse < Dex::Event::Handler
  on OrderPlaced
  retries 3

  def perform
    WarehouseApi.notify(event.order_id)
  end
end

OrderPlaced.publish(order_id: 1, total: 99.99)
```

### What you get out of the box

**Zero-config pub/sub** — define events and handlers, publish. No bus setup needed.

**Async by default** — handlers dispatched via ActiveJob. `sync: true` for inline.

**Causality tracing** — link events in chains with shared `trace_id`:

```ruby
order_placed.trace do
  InventoryReserved.publish(order_id: 1)
end
```

**Suppression**, optional **persistence**, **context capture**, and **retries** with exponential backoff.

### Testing

```ruby
class CreateOrderTest < Minitest::Test
  include Dex::Event::TestHelpers

  def test_publishes_order_placed
    capture_events do
      CreateOrder.call(item_id: 1)
      assert_event_published(OrderPlaced, order_id: 1)
    end
  end
end
```

## Installation

```ruby
gem "dexkit"
```

## Documentation

Full documentation at **[dex.razorjack.net](https://dex.razorjack.net)**.

## AI Coding Assistant Setup

Dexkit ships LLM-optimized guides. Copy them into your project so AI agents automatically know the API:

```bash
cp $(bundle show dexkit)/guides/llm/OPERATION.md app/operations/CLAUDE.md
cp $(bundle show dexkit)/guides/llm/EVENT.md app/event_handlers/CLAUDE.md
```

## License

MIT
