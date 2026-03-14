---
description: Dex::Query testing — test filters and sorts with plain Minitest against a real database. No special helpers needed.
---

# Testing

Queries return standard ActiveRecord relations or Mongoid criteria, so testing is plain Minitest – no special helpers needed.

## Setup

Queries need a database-backed scope. In tests, an in-memory SQLite database works well for ActiveRecord:

```ruby
class EmployeeQueryTest < Minitest::Test
  def setup
    Employee.create!(name: "Alice", role: "admin", salary: 90_000, status: "active")
    Employee.create!(name: "Bob", role: "user", salary: 75_000, status: "inactive")
  end
end
```

Mongoid queries work the same way once your Mongoid test database is configured:

```ruby
class EmployeeQueryTest < Minitest::Test
  def setup
    Employee.create!(name: "Alice", role: "admin", status: "active")
    Employee.create!(name: "Bob", role: "user", status: "inactive")
  end
end
```

The assertions below are identical for either backend. The only difference is the return type: `ActiveRecord::Relation` for ActiveRecord, `Mongoid::Criteria` for Mongoid.

## Testing filters

```ruby
def test_filters_by_role
  result = Employee::Query.call(role: %w[admin])
  assert_equal 1, result.count
  assert_equal "Alice", result.first.name
end

def test_contains_is_case_insensitive
  result = Employee::Query.call(name: "ali")
  assert_equal 1, result.count
end

def test_skips_nil_filters
  result = Employee::Query.call(name: nil, status: "active")
  assert_equal 1, result.count
end
```

## Testing sorts

```ruby
def test_ascending_sort
  result = Employee::Query.call(sort: "name")
  assert_equal %w[Alice Bob], result.map(&:name)
end

def test_descending_sort
  result = Employee::Query.call(sort: "-name")
  assert_equal %w[Bob Alice], result.map(&:name)
end

def test_default_sort
  result = Employee::Query.call
  assert_equal "Bob", result.first.name  # -created_at = newest first
end
```

## Testing scope injection

```ruby
def test_scope_injection
  active_employees = Employee.where(status: "active")
  result = Employee::Query.call(scope: active_employees)
  assert_equal 1, result.count
  assert_equal "Alice", result.first.name
end
```

## Testing from_params

```ruby
def test_from_params_extracts_values
  params = ActionController::Parameters.new(
    employee_query: { name: "ali", sort: "-name" }
  )
  query = Employee::Query.from_params(params)
  assert_equal "ali", query.name
  assert_equal "-name", query.sort
end

def test_from_params_drops_invalid_sort
  params = ActionController::Parameters.new(
    employee_query: { sort: "nonexistent" }
  )
  query = Employee::Query.from_params(params)
  assert_equal "-created_at", query.sort  # falls back to default
end
```

## Testing to_params

```ruby
def test_to_params_round_trip
  query = Employee::Query.new(name: "ali", sort: "-name")
  assert_equal({ name: "ali", sort: "-name" }, query.to_params)
end

def test_to_params_omits_nil_values
  query = Employee::Query.new
  refute query.to_params.key?(:name)
end
```

## Testing shortcuts

```ruby
def test_count
  assert_equal 2, Employee::Query.count
  assert_equal 1, Employee::Query.count(role: %w[admin])
end

def test_exists
  assert Employee::Query.exists?(name: "Alice")
  refute Employee::Query.exists?(name: "Nobody")
end
```
