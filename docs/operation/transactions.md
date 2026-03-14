---
description: Dex::Operation transactions — enabled by default, with automatic rollback on errors, after_commit hooks, and per-operation configuration.
---

# Transactions

Operations run inside database transactions when Dex has an active transaction adapter. ActiveRecord is auto-detected – no configuration needed.

## Default behavior

With ActiveRecord, you don't need to do anything – transactions are on by default:

```ruby
class Order::Place < Dex::Operation
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
class Order::Report < Dex::Operation
  transaction false

  def perform
    Report.generate(Date.today)
  end
end
```

## Interaction with error! and success!

`error!` triggers a rollback – any database changes made during `perform` are undone. `success!` commits the transaction normally.

```ruby
class Order::Refund < Dex::Operation
  prop :order, _Ref(Order, lock: true)
  prop :customer, _Ref(Customer, lock: true)
  prop :amount, Integer

  def perform
    order.update!(refunded_amount: order.refunded_amount + amount)
    customer.update!(credit: customer.credit + amount)

    error!(:exceeds_total) if order.refunded_amount > order.total
    # Both updates are rolled back
  end
end
```

## after_commit

Register blocks inside `perform` that run only after the transaction commits. Use this for side effects that shouldn't fire on rollback – emails, webhooks, cache invalidation:

```ruby
class Employee::Onboard < Dex::Operation
  prop :email, String
  prop :name, String

  error :email_taken

  def perform
    error!(:email_taken) if Employee.exists?(email: email)

    employee = Employee.create!(name: name, email: email)

    after_commit { OnboardingMailer.with(employee: employee).deliver_later }
    after_commit { Analytics.track(:employee_onboarded, employee_id: employee.id) }

    employee
  end
end
```

Multiple blocks run in registration order.

**On rollback** (`error!` or exception), callbacks are discarded – they never fire.

**Without a database transaction**, `after_commit` still defers until the operation pipeline succeeds, then runs the block. This includes Mongoid-only apps where no transaction adapter is active.

**Nested operations** work correctly – an inner operation's `after_commit` blocks are deferred until the outermost transaction commits. If the outer transaction rolls back, inner callbacks are discarded too.

::: warning ActiveRecord requires Rails 7.2+
`after_commit` uses `ActiveRecord.after_all_transactions_commit` under the hood, which was introduced in Rails 7.2. On older Rails versions, calling `after_commit` raises `LoadError`.
:::

## Mongoid

Dex does not manage Mongoid transactions. In Mongoid-only apps, the transaction adapter is `nil`, so transactions are automatically disabled – but `after_commit` still works (callbacks fire immediately after the pipeline succeeds).

If you need multi-document transactions in a Mongoid app, call `Mongoid.transaction` directly inside `perform`:

```ruby
class Order::Place < Dex::Operation
  transaction false

  def perform
    Mongoid.transaction do
      order = Order.create!(total: 100)
      LineItem.create!(order: order, product: "Widget")
    end
  end
end
```

## Inheritance

Transaction settings inherit. A common pattern is a base class that disables transactions:

```ruby
class ReadOperation < Dex::Operation
  transaction false
end

class Employee::List < ReadOperation
  def perform
    Employee.all.to_a
  end
end
```
