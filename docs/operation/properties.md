---
description: Dex::Operation properties — declare typed inputs as required, optional, arrays, unions, or model references using Literal's type system.
---

# Properties & Types

Properties are the inputs to your operation. They're declared with `prop` (required) or `prop?` (optional), validated at instantiation, and accessible as instance methods.

## Required properties

```ruby
class Order::SendConfirmation < Dex::Operation
  prop :to, String
  prop :subject, String
  prop :body, String

  def perform
    ConfirmationMailer.send(to: to, subject: subject, body: body)
  end
end

Order::SendConfirmation.call(to: "alice@example.com", subject: "Hi", body: "Hello!")
```

Missing or wrongly-typed properties raise `Literal::TypeError` immediately – you never enter `perform` with bad inputs.

## Optional properties

Use `prop?` for optional inputs. They default to `nil` unless you provide a `:default`:

```ruby
class Product::Create < Dex::Operation
  prop :title, String
  prop? :description, String                     # defaults to nil
  prop? :status, String, default: "draft"         # defaults to "draft"

  def perform
    Product.create!(title: title, description: description, status: status)
  end
end

Product::Create.call(title: "Widget")  # description: nil, status: "draft"
```

## Type system

Types are powered by the [literal](https://github.com/joeldrapper/literal) gem. Plain Ruby classes work as types, plus you get type constructors for more expressive validations. These constructors are available inside operation class bodies:

| Constructor | Meaning | Example |
|---|---|---|
| `String`, `Integer`, etc. | Exact class match | `prop :name, String` |
| `_Nilable(T)` | `T` or `nil` | `prop :bio, _Nilable(String)` |
| `_Array(T)` | Array of T | `prop :tags, _Array(String)` |
| `_Integer(range)` | Integer in range | `prop :age, _Integer(0..150)` |
| `_Union(...)` | One of several values | `prop :currency, _Union("USD", "EUR")` |
| `_Ref(Model)` | Model reference (see below) | `prop :customer, _Ref(Customer)` |

```ruby
class Order::Refund < Dex::Operation
  prop :amount, _Integer(1..)
  prop :currency, _Union("USD", "EUR", "GBP")
  prop :note, _Nilable(String)
  prop :tags, _Array(String), default: -> { [] }

  def perform
    # amount is guaranteed to be a positive Integer
    # currency is guaranteed to be one of the three strings
    # ...
  end
end
```

## Model references with `_Ref`

`_Ref(Model)` is a special type for model references. It accepts either a model instance or an ID, and automatically finds the record:

```ruby
class Order::Cancel < Dex::Operation
  prop :order, _Ref(Order)
  prop :customer, _Ref(Customer)

  def perform
    order.update!(cancelled: true, cancelled_by: customer)
  end
end

# Both work – pass an instance or an ID
Order::Cancel.call(order: Order.find(1), customer: current_customer)
Order::Cancel.call(order: 1, customer: 42)
```

Inside `perform`, the property is always a model instance – the lookup happens during initialization.

### Optional refs

```ruby
class Employee::Update < Dex::Operation
  prop :employee, _Ref(Employee)
  prop? :department, _Ref(Department)   # can be nil

  def perform
    employee.update!(department: department) if department
  end
end

Employee::Update.call(employee: 1, department: nil)  # works fine
```

### Locking refs

Pass `lock: true` to acquire a row lock (`SELECT ... FOR UPDATE`) when fetching:

```ruby
class Order::Debit < Dex::Operation
  prop :order, _Ref(Order, lock: true)

  def perform
    order.update!(balance: order.balance - 100)
  end
end

# Executes: Order.lock.find(42)
Order::Debit.call(order: 42)
```

This is especially useful inside transactions to prevent race conditions.

`lock: true` requires a model class that responds to `.lock` (ActiveRecord models). Mongoid documents do not support row locks and raise `ArgumentError` at declaration time.

## Serialization

Properties serialize cleanly for async jobs and recording. Ref types serialize as IDs, everything else uses `.as_json`:

```ruby
class Order::Charge < Dex::Operation
  prop :customer, _Ref(Customer)
  prop :amount, Integer

  def perform
    # ...
  end
end

op = Order::Charge.new(customer: 42, amount: 100)
# Internal serialization: {"customer" => 42, "amount" => 100}
```

Types like `Date`, `Time`, `BigDecimal`, and `Symbol` automatically survive the JSON round-trip when used with async – no manual conversion needed. Mongoid `BSON::ObjectId` ref IDs are serialized safely too.

## Reader visibility

By default, all properties have public readers. You can change this:

```ruby
class Shipment::Track < Dex::Operation
  prop :api_key, String, reader: :private

  def perform
    # api_key is accessible here (private method)
    call_api(api_key)
  end
end

op = Shipment::Track.new(api_key: "sk-123")
op.api_key  # => NoMethodError (private)
```

## Property descriptions

Add `desc:` to document what a property represents. Descriptions appear in [contract export](/tooling/registry#exporting-contracts), JSON Schema output, and LLM tool definitions:

```ruby
class Order::Place < Dex::Operation
  prop :customer, _Ref(Customer), desc: "The customer placing the order"
  prop :quantity, _Integer(1..), desc: "Number of units (minimum 1)"
  prop? :note, String, desc: "Optional note for the warehouse"

  def perform
    # ...
  end
end
```

`desc:` works on both `prop` and `prop?`. It's purely for introspection – it has no effect on validation or runtime behavior.

## Reserved names

A few names are reserved and can't be used as property names: `call`, `perform`, `async`, `safe`, `initialize`. Using them raises `ArgumentError` at class definition time.
