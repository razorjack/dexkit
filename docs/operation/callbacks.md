# Callbacks

Hook into the operation lifecycle with `before`, `after`, and `around`. Callbacks run inside the transaction boundary, so errors in callbacks trigger a rollback.

## before

Runs before `perform`. Use it for validation, setup, or precondition checks.

```ruby
class Order::Place < Dex::Operation
  prop :product_id, Integer
  prop :quantity, _Integer(1..)

  before :check_stock

  def perform
    Order.create!(product_id: product_id, quantity: quantity)
  end

  private

  def check_stock
    stock = Product.find(product_id).stock
    error!(:out_of_stock, "Only #{stock} left") if stock < quantity
  end
end
```

Calling `error!` in a `before` callback stops execution – `perform` is never reached.

## after

Runs after `perform` succeeds (or after `success!`). Skipped if `perform` raises or calls `error!`.

```ruby
class Employee::Onboard < Dex::Operation
  prop :email, String

  after :send_onboarding_email

  def perform
    Employee.create!(email: email)
  end

  private

  def send_onboarding_email
    OnboardingMailer.deliver_later(email: email)
  end
end
```

## around

Wraps the entire before/perform/after sequence. Your callback must yield (or call the continuation) to proceed – otherwise `perform` is never invoked.

```ruby
class Product::Import < Dex::Operation
  around :with_timing

  def perform
    # heavy work
  end

  private

  def with_timing
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    Rails.logger.info "Product::Import took #{elapsed.round(2)}s"
  end
end
```

## Callback forms

All three callbacks accept a Symbol (method name), a block, or a callable (lambda/proc):

```ruby
class Order::Process < Dex::Operation
  # Symbol – calls the named method
  before :validate_stock

  # Block – executed via instance_exec (has access to props, error!, etc.)
  before { error!(:closed) if store_closed? }

  # Lambda – for around, receives a continuation
  around ->(cont) {
    Rails.logger.tagged("Order::Process") { cont.call }
  }

  # ...
end
```

## Execution order

Multiple callbacks of the same type run in declaration order:

```ruby
class Order::Place < Dex::Operation
  before :first
  before :second
  before :third

  # Runs: first → second → third → perform
end
```

The full callback execution order is:

```
around do
  before callbacks (in order)
  perform
  after callbacks (in order)
end
```

## Inheritance

Callbacks inherit from parent classes. Parent callbacks run first, then child callbacks:

```ruby
class BaseOperation < Dex::Operation
  before { Rails.logger.info "Base before" }
end

class ChildOperation < BaseOperation
  before { Rails.logger.info "Child before" }

  def perform
    # Runs: "Base before" → "Child before" → perform
  end
end
```

## Interaction with error! and success!

- `error!` in a `before` callback prevents `perform` and `after` from running
- `error!` in `perform` prevents `after` from running
- `success!` in `perform` still runs `after` callbacks (the operation succeeded)
- `error!` anywhere rolls back the transaction
