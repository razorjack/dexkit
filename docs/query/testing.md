# Testing

Queries return standard ActiveRecord relations, so testing is plain Minitest – no special helpers needed.

## Setup

Queries need a database. In tests, an in-memory SQLite database works well:

```ruby
class UserSearchTest < Minitest::Test
  def setup
    User.create!(name: "Alice", role: "admin", age: 30, status: "active")
    User.create!(name: "Bob", role: "user", age: 25, status: "inactive")
  end
end
```

## Testing filters

```ruby
def test_filters_by_role
  result = UserSearch.call(role: %w[admin])
  assert_equal 1, result.count
  assert_equal "Alice", result.first.name
end

def test_contains_is_case_insensitive
  result = UserSearch.call(name: "ali")
  assert_equal 1, result.count
end

def test_skips_nil_filters
  result = UserSearch.call(name: nil, status: "active")
  assert_equal 1, result.count
end
```

## Testing sorts

```ruby
def test_ascending_sort
  result = UserSearch.call(sort: "name")
  assert_equal %w[Alice Bob], result.map(&:name)
end

def test_descending_sort
  result = UserSearch.call(sort: "-name")
  assert_equal %w[Bob Alice], result.map(&:name)
end

def test_default_sort
  result = UserSearch.call
  assert_equal "Bob", result.first.name  # -created_at = newest first
end
```

## Testing scope injection

```ruby
def test_scope_injection
  active_users = User.where(status: "active")
  result = UserSearch.call(scope: active_users)
  assert_equal 1, result.count
  assert_equal "Alice", result.first.name
end
```

## Testing from_params

```ruby
def test_from_params_extracts_values
  params = ActionController::Parameters.new(
    user_search: { name: "ali", sort: "-name" }
  )
  query = UserSearch.from_params(params)
  assert_equal "ali", query.name
  assert_equal "-name", query.sort
end

def test_from_params_drops_invalid_sort
  params = ActionController::Parameters.new(
    user_search: { sort: "nonexistent" }
  )
  query = UserSearch.from_params(params)
  assert_equal "-created_at", query.sort  # falls back to default
end
```

## Testing to_params

```ruby
def test_to_params_round_trip
  query = UserSearch.new(name: "ali", sort: "-name")
  assert_equal({ name: "ali", sort: "-name" }, query.to_params)
end

def test_to_params_omits_nil_values
  query = UserSearch.new
  refute query.to_params.key?(:name)
end
```

## Testing shortcuts

```ruby
def test_count
  assert_equal 2, UserSearch.count
  assert_equal 1, UserSearch.count(role: %w[admin])
end

def test_exists
  assert UserSearch.exists?(name: "Alice")
  refute UserSearch.exists?(name: "Nobody")
end
```
