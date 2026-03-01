# Properties & Types

Properties are the inputs to your operation. They're declared with `prop` (required) or `prop?` (optional), validated at instantiation, and accessible as instance methods.

## Required properties

```ruby
class SendEmail < Dex::Operation
  prop :to, String
  prop :subject, String
  prop :body, String

  def perform
    Mailer.send(to: to, subject: subject, body: body)
  end
end

SendEmail.call(to: "alice@example.com", subject: "Hi", body: "Hello!")
```

Missing or wrongly-typed properties raise `Literal::TypeError` immediately – you never enter `perform` with bad inputs.

## Optional properties

Use `prop?` for optional inputs. They default to `nil` unless you provide a `:default`:

```ruby
class CreatePost < Dex::Operation
  prop :title, String
  prop? :body, String                     # defaults to nil
  prop? :status, String, default: "draft"   # defaults to "draft"

  def perform
    Post.create!(title: title, body: body, status: status)
  end
end

CreatePost.call(title: "Hello")  # body: nil, status: "draft"
```

## Type system

Types are powered by the [literal](https://github.com/joeldrapper/literal) gem. Plain Ruby classes work as types, plus you get type constructors for more expressive validations. These constructors are available inside operation class bodies:

| Constructor | Meaning | Example |
|---|---|---|
| `String`, `Integer`, etc. | Exact class match | `prop :name, String` |
| `_Nilable(T)` | `T` or `nil` | `prop :bio, _Nilable(String)` |
| `_Array(T)` | Array of T | `prop :tags, _Array(String)` |
| `_Integer(range)` | Integer in range | `prop :age, _Integer(0..150)` |
| `_Union(...)` | One of several values | `prop :currency, _Union("USD", "EUR")` |
| `_Ref(Model)` | Model reference (see below) | `prop :user, _Ref(User)` |

```ruby
class TransferMoney < Dex::Operation
  prop :amount, _Integer(1..)
  prop :currency, _Union("USD", "EUR", "GBP")
  prop :note, _Nilable(String)
  prop :tags, _Array(String), default: -> { [] }

  def perform
    # amount is guaranteed to be a positive Integer
    # currency is guaranteed to be one of the three strings
    # ...
  end
end
```

## Model references with `_Ref`

`_Ref(Model)` is a special type for ActiveRecord/Mongoid models. It accepts either a model instance or an ID, and automatically finds the record:

```ruby
class ArchiveProject < Dex::Operation
  prop :project, _Ref(Project)
  prop :user, _Ref(User)

  def perform
    project.update!(archived: true, archived_by: user)
  end
end

# Both work – pass an instance or an ID
ArchiveProject.call(project: Project.find(1), user: current_user)
ArchiveProject.call(project: 1, user: 42)
```

Inside `perform`, the property is always a model instance – the lookup happens during initialization.

### Optional refs

```ruby
class UpdateProfile < Dex::Operation
  prop :user, _Ref(User)
  prop? :avatar, _Ref(Avatar)   # can be nil

  def perform
    user.update!(avatar: avatar) if avatar
  end
end

UpdateProfile.call(user: 1, avatar: nil)  # works fine
```

### Locking refs

Pass `lock: true` to acquire a row lock (`SELECT ... FOR UPDATE`) when fetching:

```ruby
class DebitAccount < Dex::Operation
  prop :account, _Ref(Account, lock: true)

  def perform
    account.update!(balance: account.balance - 100)
  end
end

# Executes: Account.lock.find(42)
DebitAccount.call(account: 42)
```

This is especially useful inside transactions to prevent race conditions.

## Serialization

Properties serialize cleanly for async jobs and recording. Ref types serialize as IDs, everything else uses `.as_json`:

```ruby
class Example < Dex::Operation
  prop :user, _Ref(User)
  prop :amount, Integer

  def perform
    # ...
  end
end

op = Example.new(user: 42, amount: 100)
# Internal serialization: {"user" => 42, "amount" => 100}
```

Types like `Date`, `Time`, `BigDecimal`, and `Symbol` automatically survive the JSON round-trip when used with async – no manual conversion needed.

## Reader visibility

By default, all properties have public readers. You can change this:

```ruby
class Secret < Dex::Operation
  prop :api_key, String, reader: :private

  def perform
    # api_key is accessible here (private method)
    call_api(api_key)
  end
end

op = Secret.new(api_key: "sk-123")
op.api_key  # => NoMethodError (private)
```

## Reserved names

A few names are reserved and can't be used as property names: `call`, `perform`, `async`, `safe`, `initialize`. Using them raises `ArgumentError` at class definition time.
