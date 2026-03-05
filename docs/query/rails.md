# Rails Integration

Queries integrate with Rails forms and controllers through ActiveModel compatibility – `model_name`, `to_params`, and the `from_params` boundary method.

## Controller pattern

```ruby
class EmployeesController < ApplicationController
  def index
    @query = Employee::Query.from_params(params, scope: policy_scope(Employee))
    @employees = pagy(@query.resolve)
  end
end
```

## from_params

`from_params` handles the messy work of extracting search parameters from a controller request:

```ruby
Employee::Query.from_params(params)
Employee::Query.from_params(params, scope: current_department.employees)
Employee::Query.from_params(params, scope: current_department.employees, department: current_department)
```

Here's what it does, in order:

1. **Extracts** the nested hash from `params[param_key]` (e.g., `params[:employee_query]`). Falls back to flat params if the key is missing.
2. **Pulls out** the `sort` value and validates it against declared sorts. Invalid sorts are silently dropped (falls back to default).
3. **Strips** blank strings to `nil` for optional props.
4. **Compacts** array blanks – `["admin", ""]` becomes `["admin"]`.
5. **Coerces** string values to their declared types (Integer, Float, Date, Time, DateTime, BigDecimal). Values that can't be coerced are dropped to `nil`.
6. **Skips** `_Ref` typed props entirely – they must be passed as keyword overrides. This prevents ID injection from user input.
7. **Merges** keyword overrides last, so controller-pinned values always win.
8. **Returns** a query instance (not a relation – call `.resolve` to execute).

## Search forms

Queries work with `form_with` for search forms:

```erb
<%= form_with model: @query, url: employees_path, method: :get do |f| %>
  <%= f.text_field :name, placeholder: "Search by name" %>
  <%= f.select :status, %w[active inactive], include_blank: "Any status" %>
  <%= f.hidden_field :sort, value: @query.sort %>
  <%= f.submit "Search" %>
<% end %>
```

## param_key

By default, the param key derives from the class name (`Employee::Query` → `employee_query`). Override it when you want shorter URLs:

```ruby
class Employee::Query < Dex::Query
  param_key :q
  # params[:q][:name] instead of params[:employee_query][:name]
end
```

## to_params

Returns a hash of non-nil prop values plus the current sort – useful for generating links that preserve search state:

```ruby
query = Employee::Query.new(name: "ali", sort: "-name")
query.to_params  # => { name: "ali", sort: "-name" }
```

```erb
<%= link_to "Sort by name", employees_path(@query.to_params.merge(sort: "name")) %>
```

## model_name

Derived from the class name by default. When `param_key` is set explicitly, `model_name` adapts to match. Anonymous classes fall back to `"Query"`.
