---
description: Use Dex::Query filters with built-in strategies and custom blocks for ActiveRecord and Mongoid search behavior.
---

# Filtering

Filters connect props to query conditions. Each filter references a prop by name and applies a strategy (or a custom block) to narrow the scope.

## Built-in strategies

| Strategy | SQL equivalent | Example |
|---|---|---|
| `:eq` (default) | `= value` | `filter :status` |
| `:not_eq` | `!= value` | `filter :status, :not_eq` |
| `:contains` | `LIKE %value%` | `filter :name, :contains` |
| `:starts_with` | `LIKE value%` | `filter :name, :starts_with` |
| `:ends_with` | `LIKE %value` | `filter :name, :ends_with` |
| `:gt` | `> value` | `filter :salary, :gt` |
| `:gte` | `>= value` | `filter :salary_min, :gte, column: :salary` |
| `:lt` | `< value` | `filter :salary, :lt` |
| `:lte` | `<= value` | `filter :salary_max, :lte, column: :salary` |
| `:in` | `IN (values)` | `filter :roles, :in, column: :role` |
| `:not_in` | `NOT IN (values)` | `filter :excluded, :not_in, column: :role` |

String strategies (`:contains`, `:starts_with`, `:ends_with`) are case-insensitive. Wildcards in user input are auto-sanitized – no manual escaping needed.

The adapter is auto-detected from the scope: ActiveRecord uses Arel `matches` (LIKE), Mongoid uses case-insensitive regex.

## Column mapping

When the prop name doesn't match the database column, use `column:`:

```ruby
class Order::Query < Dex::Query
  scope { Order.all }

  prop? :total_min, Integer
  prop? :total_max, Integer

  filter :total_min, :gte, column: :total
  filter :total_max, :lte, column: :total
end
```

Multiple filters can target the same column – they compose as AND conditions.

## Custom blocks

For anything the built-in strategies can't express, use a block. The block receives the current scope and the prop value:

```ruby
prop? :search, String
filter(:search) do |scope, value|
  sanitized = ActiveRecord::Base.sanitize_sql_like(value)
  scope.where("name LIKE ? OR email LIKE ?", "%#{sanitized}%", "%#{sanitized}%")
end
```

::: warning
Built-in strategies sanitize LIKE wildcards automatically. Block filters don't – sanitize manually when using raw LIKE patterns.
:::

## Nil skipping

Optional props (`prop?`) automatically skip their filter when the value is nil. No conditional logic needed:

```ruby
prop? :status, String
filter :status              # skipped entirely when status is nil
```

`:in` and `:not_in` also skip when the value is an empty array – querying `WHERE role IN ()` is never useful.

## Block filters returning nil

If a block filter returns `nil`, the scope is preserved unchanged. This is useful for conditional logic inside the block:

```ruby
filter(:search) do |scope, value|
  scope.where("name LIKE ?", "%#{value}%") if value.length >= 3
end
```

## Validation rules

Filters are validated at class definition time:

- Every filter must reference a declared prop with the same name
- Strategy must be one of the built-in strategies (or use a block instead)
- Duplicate filter names raise `ArgumentError`
