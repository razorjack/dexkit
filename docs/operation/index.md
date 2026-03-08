---
description: Build Rails service objects with Dex::Operation – typed props, structured errors, transactions, callbacks, async execution, and composable middleware.
---

# Dex::Operation

Operations are service objects that encapsulate a single business action. They bring typed properties, error handling, transactions, callbacks, and more – all in a clean, composable API.

## Basic anatomy

```ruby
class Employee::Onboard < Dex::Operation
  prop :name, String
  prop :email, String

  def perform
    Employee.create!(name: name, email: email)
  end
end
```

Every operation has a `perform` method that contains the business logic. Properties declared with `prop` become the operation's inputs – typed, validated, and available as instance methods.

## Calling an operation

```ruby
# Class-level shorthand
employee = Employee::Onboard.call(name: "Alice", email: "alice@example.com")

# Two-step form (needed for .safe and .async)
employee = Employee::Onboard.new(name: "Alice", email: "alice@example.com").call
```

Both forms do the same thing: instantiate with properties, then execute the pipeline. The two-step form is required when chaining modifiers like `.safe.call` or `.async.call`.

## What happens when you call

Behind the scenes, `call` doesn't just run `perform` – it runs it through a pipeline of wrapper steps. The default pipeline, from outermost to innermost:

```
result > once > lock > record > transaction > rescue > callbacks > perform
```

Each step wraps the next one. Transactions wrap your database calls. Callbacks hook into the lifecycle. Errors are caught and converted. You get all of this out of the box, and every step can be configured or disabled.

## Return values

Whatever `perform` returns is the operation's return value:

```ruby
class Employee::BadgeLabel < Dex::Operation
  prop :first, String
  prop :last, String

  def perform
    "#{first} #{last}"
  end
end

Employee::BadgeLabel.call(first: "John", last: "Doe")  # => "John Doe"
```

You can also halt early with `success!` or `error!` – see [Error Handling](/operation/errors) for the full story.

## Inheritance

Operations are regular Ruby classes, so inheritance works as expected:

```ruby
class BaseOperation < Dex::Operation
  transaction false  # disable transactions for all children
end

class ReadOperation < BaseOperation
  prop :id, Integer

  def perform
    Employee.find(id)
  end
end
```

Settings, callbacks, error declarations, and pipeline steps all inherit from parent classes. Child classes can override or extend anything.

## What's next

- [Properties & Types](/operation/properties) – defining inputs with type validation
- [Ambient Context](/operation/context) – auto-fill props from `current_user`, `locale`, etc.
- [Guards](/operation/guards) – inline precondition checks before `perform`
- [Error Handling](/operation/errors) – `error!`, `assert!`, `success!`, `rescue_from`
- [Ok / Err](/operation/safe-mode) – safe mode with pattern-matched results
- [Callbacks](/operation/callbacks) – `before`, `after`, `around`
- [Transactions](/operation/transactions) – automatic database transactions
- [Idempotency](/operation/once) – run-once guarantees with deduplication keys
- [Advisory Locking](/operation/advisory-lock) – database-level concurrency control
- [Async](/operation/async) – background execution via ActiveJob
- [Recording](/operation/recording) – persist operation runs to the database
- [Middleware](/operation/pipeline) – customize the execution pipeline
- [Contracts](/operation/contracts) – introspect declared props, errors, and guards
- [Testing](/operation/testing) – helpers, assertions, and stubbing
