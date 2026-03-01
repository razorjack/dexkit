# Introduction

Dexkit is a Ruby library that gives you base classes for common Rails patterns. Equip to gain +4 DEX. Right now that's `Dex::Operation` – a service object with typed properties, structured errors, transactions, and a bunch more built in.

## Why

Service objects are everywhere in Rails apps, but everyone rolls their own. You end up with inconsistent interfaces, manual error handling, no type checking on inputs, and testing that's more boilerplate than assertion. Dexkit gives you a solid foundation so you can focus on business logic.

## What you get

Here's a taste of what an operation looks like:

```ruby
class CreateUser < Dex::Operation
  prop :email, String
  prop :name, String
  prop? :role, _Union("admin", "member"), default: "member"

  success _Ref(User)
  error :email_taken

  def perform
    error!(:email_taken) if User.exists?(email: email)
    User.create!(name: name, email: email, role: role)
  end
end

user = CreateUser.call(email: "alice@example.com", name: "Alice")
```

That's a typed, transactional, self-documenting service object. Out of the box you also get:

- **Properties with type validation** – `prop`, `prop?`, model references with `_Ref(Model)`
- **Structured error handling** – `error!`, `assert!`, `success!`, `rescue_from`
- **Database transactions** – on by default, rolled back on errors
- **Callbacks** – `before`, `after`, `around`
- **Advisory locking** – database-level mutual exclusion
- **Async execution** – run operations as background jobs via ActiveJob
- **Recording** – log operation calls to your database for auditing
- **Ok / Err** – result types with pattern matching via `.safe.call`
- **Contracts** – declare and introspect inputs, outputs, and error codes
- **Testing helpers** – assertions, stubbing, spying for Minitest

## Supported ORMs

Dexkit works with both **ActiveRecord** and **Mongoid**. Transactions, recording, and model references adapt to your ORM automatically.

## Next steps

- [Installation](/guide/installation) – add the gem and configure your app
- [Operation Overview](/operation/) – learn the basics
