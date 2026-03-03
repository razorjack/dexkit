# Attributes & Normalization

## Declaring attributes

Attributes are declared with `attribute`, using ActiveModel's type system:

```ruby
class ProfileForm < Dex::Form
  attribute :name, :string
  attribute :age, :integer
  attribute :bio, :string
  attribute :active, :boolean, default: true
  attribute :born_on, :date
end
```

Values are type-cast on assignment – `"30"` becomes `30` for an integer attribute, `"1"` becomes `true` for a boolean.

### Available types

| Type | Ruby class | Casts from |
|------|-----------|------------|
| `:string` | `String` | anything via `.to_s` |
| `:integer` | `Integer` | `"42"` → `42` |
| `:float` | `Float` | `"3.14"` → `3.14` |
| `:decimal` | `BigDecimal` | `"9.99"` → `BigDecimal("9.99")` |
| `:boolean` | `TrueClass`/`FalseClass` | `"1"`, `"true"` → `true` |
| `:date` | `Date` | `"2024-01-15"` → `Date` |
| `:datetime` | `DateTime` | ISO 8601 strings |
| `:time` | `Time` | ISO 8601 strings |

### Defaults

```ruby
attribute :role, :string, default: "member"
attribute :tags, :string   # defaults to nil
```

## Normalization

`normalizes` transforms values on every assignment – during initialization, `assign_attributes`, or direct setter calls:

```ruby
class SignupForm < Dex::Form
  attribute :email, :string
  attribute :phone, :string

  normalizes :email, with: -> { _1&.strip&.downcase.presence }
  normalizes :phone, with: -> { _1&.gsub(/\D/, "").presence }
end

form = SignupForm.new(email: "  ALICE@EXAMPLE.COM  ", phone: "(555) 123-4567")
form.email  # => "alice@example.com"
form.phone  # => "5551234567"

form.email = "  BOB@TEST.COM  "
form.email  # => "bob@test.com"
```

### Multiple attributes

Apply the same normalizer to several attributes at once:

```ruby
normalizes :first_name, :last_name, with: -> { _1&.strip.presence }
```

### Nil handling

If your normalizer returns `nil`, the attribute becomes `nil`. This is useful with `.presence` to convert blank strings:

```ruby
normalizes :bio, with: -> { _1&.strip.presence }

form = SignupForm.new(bio: "   ")
form.bio  # => nil
```

::: warning
`normalizes` requires Rails 7.1+. On older Rails versions, the method won't be available.
:::

## Reading and writing

```ruby
form = ProfileForm.new(name: "Alice", age: 30)

form.name               # => "Alice"
form.age                # => 30
form.name = "Bob"       # direct setter
form.assign_attributes(age: 31)  # bulk update

form.attribute_names    # => ["name", "age", "bio", "active", "born_on"]
```

## String keys

Forms accept both symbol and string keys – handy when working with ActionController params:

```ruby
form = ProfileForm.new("name" => "Alice", "age" => "30")
form.name  # => "Alice"
form.age   # => 30
```
