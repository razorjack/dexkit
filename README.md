# Dexkit

Rails patterns toolbelt. Equip to gain +4 DEX.

**[Documentation](https://dex.razorjack.net)**

## Operations

Service objects with typed properties, transactions, error handling, and more.

```ruby
class CreateUser < Dex::Operation
  prop :name,  String
  prop :email, String

  success _Ref(User)
  error   :email_taken

  def perform
    error!(:email_taken) if User.exists?(email: email)
    User.create!(name: name, email: email)
  end
end

user = CreateUser.call(name: "Alice", email: "alice@example.com")
user.name  # => "Alice"
```

### What you get out of the box

**Typed properties** – powered by [literal](https://github.com/joeldrapper/literal). Plain classes, ranges, unions, arrays, nilable, and model references with auto-find:

```ruby
prop :amount,   _Integer(1..)
prop :currency, _Union("USD", "EUR", "GBP")
prop :user,     _Ref(User)           # accepts User instance or ID
prop? :note,    String               # optional (nil by default)
```

**Structured errors** with `error!`, `assert!`, and `rescue_from`:

```ruby
user = assert!(:not_found) { User.find_by(id: user_id) }

rescue_from Stripe::CardError, as: :card_declined
```

**Safe mode** – returns `Ok`/`Err` instead of raising, with pattern matching:

```ruby
include Dex::Match

case CreateUser.new(email: email).safe.call
in Ok(name:)
  puts "Welcome, #{name}!"
in Err(code: :email_taken)
  puts "Already registered"
end
```

**Async execution** via ActiveJob:

```ruby
SendWelcomeEmail.new(user_id: 123).async(queue: "mailers").call
```

**Transactions** on by default, **advisory locking**, **recording** to database, **callbacks**, and a customizable **pipeline** – all composable, all optional.

### Testing

First-class test helpers for Minitest:

```ruby
class CreateUserTest < Minitest::Test
  testing CreateUser

  def test_creates_user
    assert_operation(name: "Alice", email: "alice@example.com")
  end

  def test_rejects_duplicate_email
    assert_operation_error(:email_taken, name: "Alice", email: "taken@example.com")
  end
end
```

## Installation

```ruby
gem "dexkit"
```

## Documentation

Full documentation at **[dex.razorjack.net](https://dex.razorjack.net)**.

## AI Coding Assistant Setup

Dexkit ships LLM-optimized guides. Copy them into your project so AI agents automatically know the API:

```bash
cp $(bundle show dexkit)/guides/llm/OPERATION.md app/operations/CLAUDE.md
cp $(bundle show dexkit)/guides/llm/TESTING.md test/CLAUDE.md
```

## License

MIT
