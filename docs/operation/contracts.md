---
description: Declare and introspect Dex::Operation input, success, and error contracts for runtime validation and testing.
---

# Contracts

Contracts let you declare and introspect an operation's interface – what it accepts, what it returns, and which errors it can raise.

## Declaring a success type

Use `success` to declare the expected return type. The return value of `perform` is validated at runtime:

```ruby
class Employee::Find < Dex::Operation
  prop :employee_id, Integer

  success _Ref(Employee)

  def perform
    employee = Employee.find_by(id: employee_id)
    error!(:not_found) unless employee
    employee
  end
end

Employee::Find.call(employee_id: 1)  # => Employee instance (validated)
```

Returning a mismatched type raises `ArgumentError` immediately. Returning `nil` is always allowed (even with a success type declared).

## Declaring error codes

Use `error` to declare which error codes the operation may raise:

```ruby
class Employee::Onboard < Dex::Operation
  prop :email, String

  error :email_taken, :invalid_email

  def perform
    error!(:email_taken) if Employee.exists?(email: email)
    Employee.create!(email: email)
  end
end
```

When error codes are declared, calling `error!` with an undeclared code raises `ArgumentError` – a programming mistake caught at runtime. See [Error Handling](/operation/errors#declared-error-codes) for details.

## Description

Use `description` to document what the operation does, and `desc:` on individual props for per-field documentation. These flow into contract introspection, JSON Schema export, and LLM tool definitions – see [Registry & Export](/operation/registry) for the full story.

```ruby
class Employee::Onboard < Dex::Operation
  description "Onboard a new employee"

  prop :name, String, desc: "Full legal name"
  prop :email, String, desc: "Corporate email address"

  def perform
    Employee.create!(name: name, email: email)
  end
end
```

## Introspecting with .contract

Every operation exposes a `.contract` class method that returns a frozen `Contract` data object:

```ruby
Employee::Onboard.contract
# => #<data Dex::Operation::Contract
#      params={email: String},
#      success=nil,
#      errors=[:email_taken, :invalid_email],
#      guards=[]>
```

The contract has four fields:

| Field | Type | Description |
|---|---|---|
| `params` | `Hash{Symbol => Type}` | Declared properties and their types |
| `success` | Type or `nil` | Declared success type |
| `errors` | `Array<Symbol>` | Declared error codes (includes guard codes) |
| `guards` | `Array<Hash>` | Guard metadata (name, message, requires) |

See [Guards](/operation/guards) for details on declaring and introspecting guards.

## Pattern matching on contracts

`Contract` is a `Data.define`, so it supports pattern matching and `to_h`:

```ruby
Employee::Onboard.contract => { params:, success:, errors:, guards: }

params   # => { email: String }
success  # => nil
errors   # => [:email_taken, :invalid_email]
guards   # => []

Employee::Onboard.contract.to_h
# => { params: { email: String }, success: nil, errors: [:email_taken, :invalid_email], guards: [] }
```

## Inheritance

Contracts inherit from parent classes. A child class's declared errors are merged with the parent's:

```ruby
class BaseOperation < Dex::Operation
  error :unauthorized
end

class Employee::Onboard < BaseOperation
  error :email_taken

  def perform
    error!(:unauthorized)  # works – inherited from parent
    error!(:email_taken)   # works – declared on this class
  end
end

Employee::Onboard.contract.errors  # => [:unauthorized, :email_taken]
```

Success types also inherit – a child class can override the parent's success type.

## Use cases

Contracts are useful for:

- **Documentation** – describe intent at the class level, not just in comments
- **Testing** – assert the contract without calling the operation (see [Testing](/operation/testing#contract-assertions))
- **Tooling** – build admin panels, API docs, or monitoring dashboards from contract data
- **Export** – serialize contracts as hashes or JSON Schema for external tools (see [Registry & Export](/operation/registry))
- **LLM integration** – turn operations into LLM-callable tools (see [LLM Tools](/operation/llm-tools))
- **Catching mistakes** – typos in error codes and wrong return types are caught at runtime
