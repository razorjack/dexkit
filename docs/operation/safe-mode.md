# Safe Mode (Ok / Err)

By default, operations raise `Dex::Error` on failure. Safe mode wraps the result in `Ok` or `Err` instead, making error handling explicit and enabling pattern matching.

## Basic usage

```ruby
result = CreateUser.new(email: "alice@example.com").safe.call

if result.ok?
  puts "Created user: #{result.value.name}"
else
  puts "Failed: #{result.code} – #{result.message}"
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

## Pattern matching

Both `Ok` and `Err` support Ruby's pattern matching. Include `Dex::Match` for cleaner syntax:

```ruby
include Dex::Match

result = FindUser.new(user_id: 123).safe.call

case result
in Ok(name:, email:)
  puts "Found #{name} (#{email})"
in Err(code: :not_found)
  puts "User not found"
in Err(code:, message:)
  puts "Error #{code}: #{message}"
end
```

Without `Dex::Match`, use the fully qualified names:

```ruby
case result
in Dex::Ok
  # ...
in Dex::Err(code: :not_found)
  # ...
end
```

### How pattern matching works

`Ok` deconstructs by delegating to its value – if the value is a Hash or responds to `deconstruct_keys`, you can match its contents directly:

```ruby
case result
in Ok(name: /Alice/)
  # matches when value[:name] matches /Alice/
end
```

`Err` deconstructs into `{ code:, message:, details: }`:

```ruby
case result
in Err(code: :not_found, message:)
  puts message
end
```

## When to use safe mode

Safe mode is great when you want to handle errors as values rather than exceptions:

```ruby
# In a controller
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

```ruby
# Composing operations
user_result = CreateUser.new(email: email).safe.call
return if user_result.error?

SendWelcomeEmail.call(user_id: user_result.value.id)
```

For fire-and-forget calls where you just want exceptions to propagate, the regular `.call` is simpler.
