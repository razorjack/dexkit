# Sorting

Sorts declare which columns (or custom orderings) are available. At call time, the caller picks one and optionally reverses direction with a `-` prefix.

## Column sorts

```ruby
sort :name, :created_at, :salary
```

Declare multiple columns at once or one at a time. At call time, prefix with `-` for descending:

```ruby
Employee::Query.call(sort: "name")          # ORDER BY name ASC
Employee::Query.call(sort: "-created_at")   # ORDER BY created_at DESC
```

## Custom sorts

For complex ordering that can't be expressed as a single column:

```ruby
sort(:relevance) { |scope| scope.order(Arel.sql("LENGTH(name)")) }
```

Custom sorts cannot use the `-` prefix – the direction is baked into the block. Passing `sort: "-relevance"` raises `ArgumentError`.

## Default sort

Set a default that applies when no sort is provided:

```ruby
sort :name, :created_at, default: "-created_at"
```

Only one default per class hierarchy. Attempting to set a second one raises `ArgumentError`. The default can reference any declared sort, including custom ones (without `-`).

## Introspection

```ruby
Employee::Query.sorts   # => [:name, :created_at, :salary, :relevance]
```

## Validation rules

Sorts are validated at class definition time:

- Duplicate sort names raise `ArgumentError`
- Block sorts require exactly one column name
- Default must reference an existing sort
- Custom sorts can't be used as defaults with `-` prefix
