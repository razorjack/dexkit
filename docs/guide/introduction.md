# Introduction

Dexkit is a Ruby library that gives you base classes for common Rails patterns. Equip to gain +4 DEX.

Four building blocks, each independent – use one or all:

- **[Dex::Operation](/operation/)** – service objects with typed properties, structured errors, transactions, callbacks, async execution, and more
- **[Dex::Event](/event/)** – typed immutable event objects with pub/sub, async dispatch, causality tracing, and optional persistence
- **[Dex::Form](/form/)** – form objects with typed attributes, normalization, validation, nested forms, and Rails form builder compatibility
- **[Dex::Query](/query/)** – query objects with declarative filters, sorting, type coercion from params, and Rails form binding

## A quick taste

### Operations

Typed, transactional service objects with structured error handling:

```ruby
class CreateUser < Dex::Operation
  prop :email, String
  prop :name, String
  prop? :role, _Union("admin", "member"), default: "member"

  error :email_taken

  def perform
    error!(:email_taken) if User.exists?(email: email)
    User.create!(name: name, email: email, role: role)
  end
end

user = CreateUser.call(email: "alice@example.com", name: "Alice")
```

### Events

Publish domain events, handle them sync or async:

```ruby
class OrderPlaced < Dex::Event
  prop :order_id, Integer
  prop :total, BigDecimal
end

class NotifyWarehouse < Dex::Event::Handler
  on OrderPlaced

  def perform(event)
    WarehouseApi.reserve(event.order_id)
  end
end

OrderPlaced.publish(order_id: 42, total: 99.99)
```

### Forms

User-facing input handling with nested forms and Rails integration:

```ruby
class RegistrationForm < Dex::Form
  attribute :email, :string
  attribute :name, :string

  normalizes :email, with: -> { _1&.strip&.downcase.presence }
  validates :email, :name, presence: true

  nested_one :address do
    attribute :street, :string
    attribute :city, :string
    validates :street, :city, presence: true
  end
end

form = RegistrationForm.new(params.require(:registration))
```

### Queries

Declarative filtering and sorting for ActiveRecord (and Mongoid) scopes:

```ruby
class UserSearch < Dex::Query
  scope { User.all }

  prop? :name, String
  prop? :role, _Array(String)

  filter :name, :contains
  filter :role, :in

  sort :name, :created_at, default: "-created_at"
end

users = UserSearch.call(name: "ali", role: %w[admin viewer], sort: "name")
```

## Why

Rails apps accumulate the same patterns over and over – service objects, event systems, form objects – but everyone rolls their own. You end up with inconsistent interfaces, manual error handling, no type checking, and testing that's more boilerplate than assertion. Dexkit gives you a solid foundation so you can focus on business logic.

## Supported ORMs

Dexkit works with both **ActiveRecord** and **Mongoid**. Transactions, recording, and model references adapt to your ORM automatically.

## Next steps

- [Installation](/guide/installation) – add the gem and configure your app
- [Operation Overview](/operation/) – typed service objects
- [Event Overview](/event/) – domain events and handlers
- [Form Overview](/form/) – form objects and nested forms
- [Query Overview](/query/) – declarative filtering and sorting
