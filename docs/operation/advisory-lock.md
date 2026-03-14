---
description: Dex::Operation advisory locking — serialize concurrent calls with database-backed locks, no external dependencies required.
---

# Advisory Locking

Wrap operations in database advisory locks for mutual exclusion. Only one instance with the same lock key can run at a time – others wait or time out.

Requires the [`with_advisory_lock`](https://github.com/ClosureTree/with_advisory_lock) gem (not bundled with dexkit – add it to your Gemfile).

This feature is ActiveRecord-only. In Mongoid-only apps, calling `advisory_lock` raises a clear `LoadError`.

## Basic usage

```ruby
class Order::Charge < Dex::Operation
  prop :charge_id, String

  advisory_lock { "charge:#{charge_id}" }

  def perform
    # Only one instance per charge_id runs at a time
    Stripe::Charge.create!(charge_id)
  end
end
```

## Lock key forms

```ruby
# Dynamic block – most common, has access to props
advisory_lock { "payment:#{charge_id}" }

# Static string – same lock for all instances
advisory_lock "generate-daily-report"

# Symbol – calls an instance method
advisory_lock :compute_lock_key

# No argument – uses the class name as the lock key
advisory_lock
```

## Timeout

By default, `with_advisory_lock` waits indefinitely. Set a timeout in seconds:

```ruby
class Product::Import < Dex::Operation
  advisory_lock "import", timeout: 10

  def perform
    # If another import is running, wait up to 10 seconds
    # then raise Dex::Error with code :lock_timeout
  end
end
```

On timeout, a `Dex::Error` with code `:lock_timeout` is raised. This integrates naturally with `.safe`:

```ruby
include Dex::Match

result = Product::Import.new.safe.call
case result
in Err(code: :lock_timeout)
  puts "Import already in progress"
end
```

## Pipeline position

Advisory locking runs outside the transaction boundary. The lock is acquired first, then the transaction begins. This is the correct ordering – you don't want to hold a transaction open while waiting for a lock.

```
trace > result > guard > once > lock > record > transaction > rescue > callbacks > perform
```
