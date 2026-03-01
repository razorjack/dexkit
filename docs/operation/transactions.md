# Transactions

Operations run inside database transactions by default. If anything raises – including `error!` – the transaction is rolled back. If `perform` succeeds or calls `success!`, the transaction is committed.

## Default behavior

You don't need to do anything – transactions are on by default:

```ruby
class CreateOrder < Dex::Operation
  def perform
    order = Order.create!(total: 100)
    LineItem.create!(order: order, product: "Widget")
    Payment.create!(order: order, amount: 100)
    # If any of these fail, all are rolled back
  end
end
```

## Disabling transactions

For read-only operations or cases where you manage transactions yourself:

```ruby
class FetchReport < Dex::Operation
  transaction false

  def perform
    Report.generate(Date.today)
  end
end
```

## Transaction adapters

The default adapter is `:active_record`. If you use Mongoid, configure it globally:

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  config.transaction_adapter = :mongoid
end
```

Or override per-operation:

```ruby
class MongoidOperation < Dex::Operation
  transaction adapter: :mongoid
  # or shorthand:
  transaction :mongoid
end
```

Supported adapters: `:active_record`, `:mongoid`.

## Interaction with error! and success!

`error!` triggers a rollback – any database changes made during `perform` are undone. `success!` commits the transaction normally.

```ruby
class TransferMoney < Dex::Operation
  prop :from, _Ref(Account, lock: true)
  prop :to, _Ref(Account, lock: true)
  prop :amount, Integer

  def perform
    from.update!(balance: from.balance - amount)
    to.update!(balance: to.balance + amount)

    error!(:insufficient_funds) if from.balance < 0
    # Both updates are rolled back
  end
end
```

## Inheritance

Transaction settings inherit. A common pattern is a base class that disables transactions:

```ruby
class ReadOperation < Dex::Operation
  transaction false
end

class ListUsers < ReadOperation
  def perform
    User.all.to_a
  end
end
```
