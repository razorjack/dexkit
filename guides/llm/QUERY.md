# Dex::Query — LLM Reference

Copy this to your app's queries directory (e.g., `app/queries/AGENTS.md`) so coding agents know the full API when implementing and testing queries.

---

## Reference Query

All examples below build on this query unless noted otherwise:

```ruby
class UserSearch < Dex::Query
  scope { User.all }

  prop? :name,   String
  prop? :role,   _Array(String)
  prop? :age_min, Integer
  prop? :status, String

  filter :name,    :contains
  filter :role,    :in
  filter :age_min, :gte, column: :age
  filter :status

  sort :name, :created_at, default: "-created_at"
  sort(:relevance) { |scope| scope.order(Arel.sql("LENGTH(name)")) }
end
```

---

## Defining Queries

Queries declare a base scope, typed props for filter inputs, filter strategies, and sort columns.

```ruby
class ProjectSearch < Dex::Query
  scope { Project.where(archived: false) }

  prop? :name, String
  filter :name, :contains

  sort :name, :created_at, default: "name"
end
```

### `scope { ... }`

Required. Defines the base relation. The block is `instance_exec`'d so props are accessible:

```ruby
class TaskSearch < Dex::Query
  scope { project.tasks }

  prop :project, _Ref(Project)
  prop? :status, String
  filter :status
end
```

### Props

Uses the same `prop`/`prop?`/`_Ref` DSL as Operation and Event (powered by Literal):

```ruby
prop :project,  _Ref(Project)       # required, auto-finds by ID
prop? :name,    String               # optional (nil by default)
prop? :roles,   _Array(String)       # optional array
prop? :age_min, Integer              # optional integer
```

Reserved prop names: `scope`, `sort`, `resolve`, `call`, `from_params`, `to_params`, `param_key`.

---

## Filters

### Built-in Strategies

| Strategy | SQL | Example |
|----------|-----|---------|
| `:eq` (default) | `= value` | `filter :status` |
| `:not_eq` | `!= value` | `filter :status, :not_eq` |
| `:contains` | `LIKE %value%` | `filter :name, :contains` |
| `:starts_with` | `LIKE value%` | `filter :name, :starts_with` |
| `:ends_with` | `LIKE %value` | `filter :name, :ends_with` |
| `:gt` | `> value` | `filter :age, :gt` |
| `:gte` | `>= value` | `filter :age_min, :gte, column: :age` |
| `:lt` | `< value` | `filter :age, :lt` |
| `:lte` | `<= value` | `filter :age, :lte` |
| `:in` | `IN (values)` | `filter :roles, :in, column: :role` |
| `:not_in` | `NOT IN (values)` | `filter :roles, :not_in, column: :role` |

String strategies (`:contains`, `:starts_with`, `:ends_with`) use case-insensitive matching. With ActiveRecord, this uses Arel `matches` (LIKE); with Mongoid, case-insensitive regex. Wildcards in values are auto-sanitized. The adapter is auto-detected from the scope.

### Column Mapping

Map a prop name to a different column:

```ruby
prop? :age_min, Integer
filter :age_min, :gte, column: :age
```

### Custom Filter Blocks

For complex logic, use a block. Sanitize LIKE wildcards manually (built-in strategies handle this automatically):

```ruby
prop? :search, String
filter(:search) do |scope, value|
  sanitized = ActiveRecord::Base.sanitize_sql_like(value)
  scope.where("name LIKE ? OR email LIKE ?", "%#{sanitized}%", "%#{sanitized}%")
end
```

### Nil Skipping

- Optional props (`prop?`) skip their filter when nil
- `:in` / `:not_in` strategies also skip when value is nil or empty array

---

## Sorting

### Column Sorts

```ruby
sort :name, :created_at, :age       # multiple columns at once
sort :email                          # or one at a time
```

At call time, prefix with `-` for descending:

```ruby
UserSearch.call(sort: "name")        # ASC
UserSearch.call(sort: "-created_at") # DESC
```

### Custom Sorts

```ruby
sort(:relevance) { |scope| scope.order(Arel.sql("LENGTH(name)")) }
```

Custom sorts cannot use the `-` prefix (direction is baked into the block).

### Default Sort

```ruby
sort :name, :created_at, default: "-created_at"
```

Only one default per class. Applied when no sort is provided.

---

## Calling Queries

### `.call`

Returns an ActiveRecord relation:

```ruby
users = UserSearch.call(name: "ali", role: %w[admin], sort: "-name")
users.each { |u| puts u.name }
```

### Shortcuts

```ruby
UserSearch.count(role: %w[admin])
UserSearch.exists?(name: "Alice")
UserSearch.any?(status: "active")
```

### Scope Injection

Narrow the base scope without modifying the query class:

```ruby
active_users = User.where(active: true)
UserSearch.call(scope: active_users, name: "ali")
```

The injected scope is merged via `.merge` — model must match.

### Instance Usage

```ruby
query = UserSearch.new(name: "ali", sort: "-name")
query.name    # => "ali"
query.sort    # => "-name"
result = query.resolve
```

---

## `from_params` — HTTP Boundary

Extracts, coerces, and validates params from a controller:

```ruby
UserSearch.from_params(params)
UserSearch.from_params(params, scope: current_team.users)
UserSearch.from_params(params, scope: current_team.users, project: current_project)
```

### What it does

1. Extracts the nested hash from `params[param_key]` (e.g., `params[:user_search]`); falls back to flat params if the nested key is absent
2. Extracts `sort` from that hash
3. Strips blank strings to nil for optional props
4. Compacts array blanks (`["admin", ""]` → `["admin"]`)
5. Coerces strings to typed values (Integer, Date, etc.) — drops uncoercible to nil
6. Skips `_Ref` typed props (must be passed as keyword overrides)
7. Drops invalid sort values (falls back to default)
8. Applies keyword overrides (pinned values)
9. Returns a query instance

### Controller Pattern

```ruby
class UsersController < ApplicationController
  def index
    query = UserSearch.from_params(params, scope: policy_scope(User))
    @users = pagy(query.resolve)
  end
end
```

---

## Form Binding

Queries work with `form_with` for search forms:

```ruby
# Controller
@query = UserSearch.from_params(params)

# View
<%= form_with model: @query, url: users_path, method: :get do |f| %>
  <%= f.text_field :name %>
  <%= f.select :role, %w[admin user], include_blank: true %>
  <%= f.hidden_field :sort, value: @query.sort %>
  <%= f.submit "Search" %>
<% end %>
```

### `param_key`

Override the default param key:

```ruby
class UserSearch < Dex::Query
  param_key :q
  # params[:q][:name] instead of params[:user_search][:name]
end
```

### `model_name`

Derives from class name by default. Anonymous classes fall back to "query".

### `to_params`

Returns a hash of non-nil prop values + current sort:

```ruby
query = UserSearch.new(name: "ali", sort: "-name")
query.to_params  # => { name: "ali", sort: "-name" }
```

### `persisted?`

Always returns `false` (queries are never persisted).

---

## Inheritance

Subclasses inherit filters, sorts, and props. They can add new ones or replace the scope:

```ruby
class AdminUserSearch < UserSearch
  scope { User.where(admin: true) }  # replaces parent scope

  prop? :department, String
  filter :department
end
```

---

## Testing

Queries return standard ActiveRecord relations. Test them with plain Minitest:

```ruby
class UserSearchTest < Minitest::Test
  def setup
    User.create!(name: "Alice", role: "admin", age: 30)
    User.create!(name: "Bob", role: "user", age: 25)
  end

  def test_filters_by_role
    result = UserSearch.call(role: %w[admin])
    assert_equal 1, result.count
    assert_equal "Alice", result.first.name
  end

  def test_contains_search
    result = UserSearch.call(name: "li")
    assert_equal 1, result.count
  end

  def test_sorting
    result = UserSearch.call(sort: "name")
    assert_equal %w[Alice Bob], result.map(&:name)
  end

  def test_default_sort
    result = UserSearch.call
    assert_equal "Bob", result.first.name  # -created_at = newest first
  end

  def test_scope_injection
    active = User.where(active: true)
    result = UserSearch.call(scope: active, role: %w[user])
    assert_equal 1, result.count
  end

  def test_from_params
    params = ActionController::Parameters.new(
      user_search: { name: "ali", sort: "-name" }
    )
    query = UserSearch.from_params(params)
    assert_equal "ali", query.name
    assert_equal "-name", query.sort
  end

  def test_to_params
    query = UserSearch.new(name: "ali", sort: "-name")
    assert_equal({ name: "ali", sort: "-name" }, query.to_params)
  end
end
```
