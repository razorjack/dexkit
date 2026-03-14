---
description: Use Dex::Operation.safe.call to get Ok and Err results for Ruby pattern matching instead of raised exceptions.
---

# Ok / Err

Call `.safe.call` on any operation to get an `Ok` or `Err` result instead of a raised exception. The real payoff is pattern matching – you can destructure the outcome in a `case/in` block and handle each case cleanly.

## Pattern matching

```ruby
result = Order::Place.new(customer: 42, product: 7, quantity: 2).safe.call

case result
in Ok => order
  puts "Order ##{order.id} placed!"
in Err(code: :out_of_stock)
  puts "Product is out of stock"
in Err(code:, message:)
  puts "Error #{code}: #{message}"
end
```

`Ok` and `Err` are available without prefix inside operations and forms. In other contexts (controllers, POROs), use `Dex::Ok`/`Dex::Err` or `include Dex::Match`.

Two deconstruct forms are supported:

- **Hash** `Ok(key:)` – delegates to the value's `deconstruct_keys`, so you destructure the value's contents directly
- **Array** `Ok[value]` – binds the entire value as one variable

```ruby
case result
in Dex::Ok(order_id:, total:)   # hash – destructure into the value
  redirect_to order_path(order_id)
in Dex::Ok[value]               # array – grab the whole thing
  render json: value
end
```

`Err` supports both forms too: `Err(code:, message:, details:)` for named fields, `Err[error]` for the raw `Dex::Error` instance.

## Ok

Returned when the operation succeeds. Wraps the return value.

```ruby
result = Order::Place.new(customer: 42, product: 7, quantity: 2).safe.call

result.ok?     # => true
result.error?  # => false
result.value   # => the return value from perform
result.value!  # => same as .value (just returns it)
```

`Ok` delegates method calls to its value, so you can often use it directly:

```ruby
result = Employee::Find.new(employee_id: 1).safe.call
result.name         # => delegates to employee.name
result.department   # => delegates to employee.department
```

## Err

Returned when the operation calls `error!` or a `rescue_from` mapping triggers. Wraps the `Dex::Error`.

```ruby
result = Order::Place.new(customer: 42, product: 7, quantity: 2).safe.call

result.ok?      # => false
result.error?   # => true
result.value    # => nil
result.value!   # => raises the original Dex::Error
result.code     # => :out_of_stock
result.message  # => "out_of_stock"
result.details  # => nil or Hash
```

## In controllers

```ruby
def create
  result = Order::Place.new(customer: current_user.id, product: params[:product_id],
                            quantity: params[:quantity]).safe.call

  case result
  in Dex::Ok
    redirect_to order_path(result.id)
  in Dex::Err(code: :out_of_stock)
    flash[:error] = result.message
    render :new
  end
end
```

## Composing operations

```ruby
order_result = Order::Place.new(customer: customer_id, product: product_id, quantity: 1).safe.call
return if order_result.error?

Order::SendConfirmation.call(order_id: order_result.value.id)
```

For fire-and-forget calls where you just want exceptions to propagate, the regular `.call` is simpler.
