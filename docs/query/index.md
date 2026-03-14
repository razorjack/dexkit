---
description: Dex::Query — declarative query objects for ActiveRecord and Mongoid with typed filters, sorting, scope composition, and params coercion.
---

# Dex::Query

Query objects that turn filtering and sorting into a clean, declarative API. Define your scope, declare filters with built-in strategies, add sort columns – and get back a composable relation ready for pagination.

## Quick start

```ruby
class Employee::Query < Dex::Query
  description "Search and filter employees"

  scope { Employee.all }

  prop? :name, String
  prop? :role, _Array(String)
  prop? :status, String
  prop? :tenant, String

  context tenant: :current_tenant

  filter :name, :contains
  filter :role, :in
  filter :status

  sort :name, :created_at, default: "-created_at"
end
```

```ruby
employees = Employee::Query.call(name: "ali", role: %w[admin], sort: "name")
employees.each { |e| puts e.name }
```

`call` returns a queryable scope (ActiveRecord relation or Mongoid criteria) – lazy, chainable, ready for `.limit`, `.offset`, or your pagination gem of choice.

## Scope

Every query needs a base scope. The block is evaluated in instance context, so props are accessible:

```ruby
class LeaveRequest::Query < Dex::Query
  scope { department.leave_requests.where(archived: false) }

  prop :department, _Ref(Department)
  prop? :status, String
  filter :status
end
```

## Properties

Same `prop` / `prop?` / `_Ref` DSL as Operation and Event – powered by Literal:

```ruby
prop :department, _Ref(Department)   # required model reference
prop? :name, String                  # optional string
prop? :roles, _Array(String)         # optional array
prop? :salary_min, Integer           # optional integer
```

Properties become instance methods with public readers by default.

Reserved names that can't be used as props: `scope`, `sort`, `resolve`, `call`, `from_params`, `to_params`, `param_key`.

## Description

Document query intent with a human-readable description:

```ruby
class Employee::Query < Dex::Query
  description "Search and filter employees"
end

Employee::Query.description  # => "Search and filter employees"
```

Descriptions are optional, inherited by subclasses, and included in export output.

## Context

Queries support the same `context` DSL as Operation, Event, and Form. Map props to ambient context keys so they auto-fill from `Dex.with_context`:

```ruby
class Employee::Query < Dex::Query
  scope { Employee.all }

  prop? :tenant, String
  prop? :locale, Symbol
  context tenant: :current_tenant
  context :locale

  filter :tenant
end
```

```ruby
Dex.with_context(current_tenant: "acme", locale: :en) do
  Employee::Query.call(name: "ali")  # tenant and locale auto-filled
end
```

Explicit keyword arguments always win over ambient context. Inheritance merges parent and child mappings. `context_mappings` returns the full mapping hash for introspection.

## Registry & Export

Queries extend `Registry` – the same system as Operation, Event, and Form:

```ruby
Dex::Query.registry  # => frozen Set of all named Query subclasses
```

Export individual queries or bulk-export the entire registry:

```ruby
Employee::Query.to_h
# => { name: "Employee::Query", description: "...", props: {...}, filters: [...], sorts: [...], context: {...} }

Employee::Query.to_json_schema
# => JSON Schema (Draft 2020-12) with properties, required, additionalProperties

Dex::Query.export(format: :hash)         # sorted array of all query to_h
Dex::Query.export(format: :json_schema)  # sorted array of all query schemas
```

## Calling queries

```ruby
# Class-level – returns a relation
Employee::Query.call(name: "ali", sort: "-created_at")

# Shortcuts
Employee::Query.count(role: %w[admin])
Employee::Query.exists?(name: "Alice")
Employee::Query.any?(status: "active")

# Two-step – useful when you need the query instance
query = Employee::Query.new(name: "ali", sort: "-name")
query.name   # => "ali"
query.sort   # => "-name"
result = query.resolve
```

## Scope injection

Narrow the base scope at call time without modifying the query class:

```ruby
Employee::Query.call(scope: current_department.employees, name: "ali")
```

The injected scope is merged with the base scope via `.merge`. Both must query the same model – a mismatch raises `ArgumentError`.

## Inheritance

Subclasses inherit props, filters, sorts, and the default sort. They can add new ones or replace the scope:

```ruby
class Employee::AdminQuery < Employee::Query
  scope { Employee.where(role: "admin") }

  prop? :department, String
  filter :department
end
```

Parent registries are duplicated on inheritance, so subclass changes don't affect the parent.
