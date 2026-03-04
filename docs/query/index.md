# Dex::Query

Query objects that turn filtering and sorting into a clean, declarative API. Define your scope, declare filters with built-in strategies, add sort columns – and get back a composable relation ready for pagination.

## Quick start

```ruby
class UserSearch < Dex::Query
  scope { User.all }

  prop? :name, String
  prop? :role, _Array(String)
  prop? :status, String

  filter :name, :contains
  filter :role, :in
  filter :status

  sort :name, :created_at, default: "-created_at"
end
```

```ruby
users = UserSearch.call(name: "ali", role: %w[admin], sort: "name")
users.each { |u| puts u.name }
```

`call` returns an ActiveRecord relation (or Mongoid criteria) – lazy, chainable, ready for `.limit`, `.offset`, or your pagination gem of choice.

## Scope

Every query needs a base scope. The block is evaluated in instance context, so props are accessible:

```ruby
class TaskSearch < Dex::Query
  scope { project.tasks.where(archived: false) }

  prop :project, _Ref(Project)
  prop? :status, String
  filter :status
end
```

## Properties

Same `prop` / `prop?` / `_Ref` DSL as Operation and Event – powered by Literal:

```ruby
prop :team, _Ref(Team)         # required model reference
prop? :name, String              # optional string
prop? :roles, _Array(String)     # optional array
prop? :age_min, Integer             # optional integer
```

Properties become instance methods with public readers by default.

Reserved names that can't be used as props: `scope`, `sort`, `resolve`, `call`, `from_params`, `to_params`, `param_key`.

## Calling queries

```ruby
# Class-level – returns a relation
UserSearch.call(name: "ali", sort: "-created_at")

# Shortcuts
UserSearch.count(role: %w[admin])
UserSearch.exists?(name: "Alice")
UserSearch.any?(status: "active")

# Two-step – useful when you need the query instance
query = UserSearch.new(name: "ali", sort: "-name")
query.name   # => "ali"
query.sort   # => "-name"
result = query.resolve
```

## Scope injection

Narrow the base scope at call time without modifying the query class:

```ruby
UserSearch.call(scope: current_team.users, name: "ali")
```

The injected scope is merged with the base scope via `.merge`. Both must query the same model – a mismatch raises `ArgumentError`.

## Inheritance

Subclasses inherit props, filters, sorts, and the default sort. They can add new ones or replace the scope:

```ruby
class AdminSearch < UserSearch
  scope { User.where(admin: true) }

  prop? :department, String
  filter :department
end
```

Parent registries are duplicated on inheritance, so subclass changes don't affect the parent.
