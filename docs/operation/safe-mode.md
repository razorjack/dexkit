# Ok / Err

Call `.safe.call` on any operation to get an `Ok` or `Err` result instead of a raised exception. The real payoff is pattern matching – you can destructure the outcome in a `case/in` block and handle each case cleanly.

## Pattern matching

```ruby
include Dex::Match

result = CreateUser.new(email: "alice@example.com").safe.call

case result
in Ok(name:, email:)
  puts "Welcome, #{name} (#{email})"
in Err(code: :email_taken)
  puts "Already registered"
in Err(code:, message:)
  puts "Error #{code}: #{message}"
end
```

`Ok` deconstructs by delegating to its value – if the value is a Hash or responds to `deconstruct_keys`, you can match its contents directly. `Err` deconstructs into `{ code:, message:, details: }`.

Without `Dex::Match`, use the fully qualified names:

```ruby
case result
in Dex::Ok
  # ...
in Dex::Err(code: :not_found)
  # ...
end
```

## Ok

Returned when the operation succeeds. Wraps the return value.

```ruby
result = CreateUser.new(email: "alice@example.com").safe.call

result.ok?     # => true
result.error?  # => false
result.value   # => the return value from perform
result.value!  # => same as .value (just returns it)
```

`Ok` delegates method calls to its value, so you can often use it directly:

```ruby
result = FindUser.new(user_id: 1).safe.call
result.name   # => delegates to user.name
result.email  # => delegates to user.email
```

## Err

Returned when the operation calls `error!` or a `rescue_from` mapping triggers. Wraps the `Dex::Error`.

```ruby
result = CreateUser.new(email: "taken@example.com").safe.call

result.ok?      # => false
result.error?   # => true
result.value    # => nil
result.value!   # => raises the original Dex::Error
result.code     # => :email_taken
result.message  # => "This email is already in use"
result.details  # => nil or Hash
```

## In controllers

```ruby
def create
  result = CreateUser.new(params.permit(:email, :name).to_h).safe.call

  case result
  in Dex::Ok
    redirect_to result.value
  in Dex::Err(code: :email_taken)
    flash[:error] = result.message
    render :new
  end
end
```

## Composing operations

```ruby
user_result = CreateUser.new(email: email).safe.call
return if user_result.error?

SendWelcomeEmail.call(user_id: user_result.value.id)
```

For fire-and-forget calls where you just want exceptions to propagate, the regular `.call` is simpler.
