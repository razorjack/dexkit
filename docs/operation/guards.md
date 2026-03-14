---
description: Dex::Operation guards — declare named preconditions that run before perform, with introspection for views and controllers.
---

# Guards

Guards are named precondition checks declared inline on an operation. They detect **threats** – conditions under which the operation should not proceed. The guard name is the error code, and the block detects the bad state. Truthy means the threat is present and the operation fails.

This follows the same mental model as Ruby's `raise`:

```ruby
raise "Only admins allowed" if !user.admin?
error!(:unauthorized) if !user.admin?
guard :unauthorized, "Only admins" do !user.admin? end
```

## Basic usage

```ruby
class Order::Place < Dex::Operation
  prop :customer, _Ref(Customer)
  prop :product, _Ref(Product)
  prop :quantity, _Integer(1..)

  guard :out_of_stock, "Product must be in stock" do
    !product.in_stock?
  end

  guard :credit_exceeded, "Customer has exceeded credit limit" do
    customer.credit_remaining < product.price * quantity
  end

  def perform
    Order.create!(customer: customer, product: product, quantity: quantity)
  end
end
```

The guard name is the error code. The message is the human-readable description. The block detects the threat – return `true` (or any truthy value) to block execution.

## Dependencies between guards

When guards depend on each other, use `requires:` to skip dependent guards when a dependency fails:

```ruby
class Employee::Transfer < Dex::Operation
  prop :employee, _Ref(Employee)
  prop :department, _Ref(Department)

  guard :inactive_employee, "Employee must be active" do
    !employee.active?
  end

  guard :same_department, "Employee is already in this department",
    requires: :inactive_employee do
    employee.department == department
  end
end
```

If the employee is inactive, only `:inactive_employee` is reported. `:same_department` is skipped entirely – not run, not reported.

Multiple dependencies:

```ruby
guard :invalid_transfer, "Source and target must use same currency",
  requires: [:missing_source, :missing_target] do
  source.currency != target.currency
end
```

## Execution model

- Guards run in declaration order, before `perform`
- All independent guards run – failures are collected, not short-circuited
- Guards whose `requires:` dependencies failed are skipped
- The result reports all root-cause failures, not cascading noise

## callable? – can this operation run?

Check whether guards pass without actually running the operation:

```ruby
Order::Place.callable?(customer: customer, product: product, quantity: 2)
# => true or false

# Check a specific guard
Order::Place.callable?(:out_of_stock, product: product, customer: customer, quantity: 2)
# => true (this guard passes) or false (this guard fires)
```

## callable – rich result

Returns an `Ok` or `Err` with all failure details:

```ruby
result = Order::Place.callable(customer: customer, product: product, quantity: 2)

result.ok?      # => false
result.code     # => :out_of_stock (first failure)
result.message  # => "Product must be in stock"
result.details  # => [
                #   { guard: :out_of_stock, message: "Product must be in stock" },
                #   { guard: :credit_exceeded, message: "Customer has exceeded credit limit" }
                # ]
```

`callable` bypasses the pipeline entirely – no locks, no transactions, no recording, no callbacks. It's cheap and side-effect-free.

For a richer report that includes guards plus context, idempotency, lock keys, and all other settings, see [Explain](/operation/explain).

## UI patterns

### Show or hide a button

```erb
<% if Order::Place.callable?(customer: @customer, product: @product, quantity: 1) %>
  <%= button_to "Place Order", orders_path %>
<% end %>
```

### Disabled button with reason

```erb
<% check = Order::Place.callable(customer: @customer, product: @product, quantity: 1) %>

<% if check.ok? %>
  <%= button_to "Place Order", orders_path, class: "btn-primary" %>
<% else %>
  <span class="btn-disabled" title="<%= check.message %>">Place Order</span>
<% end %>
```

### Show all blockers

```erb
<% check = Order::Place.callable(customer: @customer, product: @product, quantity: 1) %>
<% unless check.ok? %>
  <ul class="blockers">
    <% check.details.each do |failure| %>
      <li><%= failure[:message] %></li>
    <% end %>
  </ul>
<% end %>
```

### API controller

```ruby
def create
  check = Order::Place.callable(customer: @customer, product: @product, quantity: params[:quantity])

  unless check.ok?
    return render json: { error: check.code, message: check.message }, status: :unprocessable_entity
  end

  result = Order::Place.call(customer: @customer, product: @product, quantity: params[:quantity])
  render json: result
end
```

## Guards and authorization

Guards are domain feasibility checks: "is this action possible given the current state?" They work well for authorization too, especially when you don't use an authorization framework:

```ruby
guard :unauthorized, "Only the manager or HR can approve" do
  !user.hr? && user != leave_request.manager
end
```

If you use ActionPolicy or Pundit, keep authorization in the policy and domain feasibility in guards. The policy can delegate to `callable?`:

```ruby
class LeaveRequestPolicy < ApplicationPolicy
  def approve?
    (user.hr? || record.manager == user) &&
      Leave::Approve.callable?(leave_request: record, user: user)
  end
end
```

## Guards auto-declare errors

A guard implicitly registers its name as an error code – no separate `error :unauthorized` needed. The guard code is also usable with `error!` in `perform`:

```ruby
guard :unauthorized do
  !user.admin?
end

def perform
  # valid – :unauthorized was auto-declared by the guard
  error!(:unauthorized, "runtime check failed") if some_other_condition
end
```

## Contract introspection

Guard codes appear in both `contract.errors` and `contract.guards`:

```ruby
contract = Order::Place.contract

contract.errors  # => [:out_of_stock, :credit_exceeded]
contract.guards  # => [
                 #   { name: :out_of_stock, message: "Product must be in stock", requires: [] },
                 #   { name: :credit_exceeded, message: "...", requires: [] }
                 # ]
```

## Inheritance

Guards inherit from the parent class. Parent guards run first, child guards are appended:

```ruby
class BaseOperation < Dex::Operation
  guard :unauthorized do
    !user.admin?
  end
end

class Order::Cancel < BaseOperation
  guard :already_shipped, "Cannot cancel a shipped order" do
    order.shipped?
  end
end

# Both guards run: :unauthorized first, then :already_shipped
```

## Pipeline position

Guards run right after `result`, before `once`, locking, recording, and transactions:

```
trace > result > guard > once > lock > record > transaction > rescue > callbacks > perform
```

Guard failures are caught by `result` (normal `error!` behavior). If a guard block itself raises, `rescue` still applies because it wraps the inner pipeline. Callbacks don't fire when a guard fails – the operation was rejected, not attempted.

## DSL validation

`guard` validates all arguments at declaration time:

- **code** must be a Symbol
- **block** is required
- **`requires:`** must reference previously declared guard names (typos and forward references raise `ArgumentError`)
- Duplicate guard names raise `ArgumentError`
