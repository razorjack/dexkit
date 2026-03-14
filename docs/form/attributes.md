---
description: Dex::Form fields — define typed fields with defaults, auto-presence validation, ActiveModel coercion, and input normalization.
---

# Fields & Normalization

## Declaring fields

Fields are declared with `field` (required) and `field?` (optional):

```ruby
class Employee::Form < Dex::Form
  field :name, :string
  field :email, :string, desc: "Work email"
  field :department, :string, default: "Engineering"
  field? :bio, :string
  field? :priority, :integer, default: 0
end
```

`field` declares a required field – it auto-adds presence validation. `field?` declares an optional field that defaults to `nil` (unless overridden). Both delegate to ActiveModel's `attribute` under the hood, so values are type-cast on assignment – `"30"` becomes `30` for an integer field, `"1"` becomes `true` for a boolean.

### `field` vs `field?`

| | `field` | `field?` |
|---|---|---|
| **Auto-presence** | Yes – blank values are invalid | No |
| **Default** | None (unless `default:` given) | `nil` (unless `default:` given) |
| **In JSON Schema** | Listed in `required` | Not required |
| **Mirrors** | `prop` in Operation/Event | `prop?` in Operation/Event |

### Options

| Option | Description |
|--------|-------------|
| `desc:` | Human-readable description (for introspection and JSON Schema export) |
| `default:` | Default value (passed through to ActiveModel) |

All other options are forwarded to ActiveModel's `attribute`.

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

### Auto-presence validation

Required fields (`field`) automatically validate presence. If the user also writes `validates :name, presence: true`, no duplicate error is generated – the auto-presence check detects existing presence validators and skips fields already covered.

For boolean fields, `field :active, :boolean` checks for `nil` rather than `blank?` – so `false` is a valid value.

For contextual requirements, use `field?` with an explicit validator:

```ruby
field? :published_at, :datetime
validates :published_at, presence: true, on: :publish
```

### Raw `attribute` escape hatch

`attribute` remains available for edge cases where you need raw ActiveModel behavior without Dex metadata tracking:

```ruby
field :name, :string       # tracked, auto-presence, in export
attribute :temp, :string   # raw ActiveModel, not in field registry
```

## Normalization

`normalizes` transforms values on every assignment – during initialization, `assign_attributes`, or direct setter calls:

```ruby
class Employee::Form < Dex::Form
  field :email, :string
  field :phone, :string

  normalizes :email, with: -> { it&.strip&.downcase.presence }
  normalizes :phone, with: -> { it&.gsub(/\D/, "").presence }
end

form = Employee::Form.new(
  email: "  ALICE@EXAMPLE.COM  ",
  phone: "(555) 123-4567"
)
form.email  # => "alice@example.com"
form.phone  # => "5551234567"

form.email = "  BOB@TEST.COM  "
form.email  # => "bob@test.com"
```

### Multiple attributes

Apply the same normalizer to several attributes at once:

```ruby
normalizes :first_name, :last_name, with: -> { it&.strip.presence }
```

### Nil handling

If your normalizer returns `nil`, the attribute becomes `nil`. This is useful with `.presence` to convert blank strings:

```ruby
normalizes :bio, with: -> { it&.strip.presence }

form = Employee::Form.new(bio: "   ")
form.bio  # => nil
```

::: warning
`normalizes` requires Rails 7.1+. On older Rails versions, the method won't be available.
:::

## Ambient context

Forms support the same `context` DSL as Operation and Event – auto-fill fields from `Dex.context`:

```ruby
class Order::Form < Dex::Form
  field :locale, :string
  field :currency, :string

  context :locale
  context currency: :default_currency
end

Dex.with_context(locale: "en", default_currency: "USD") do
  form = Order::Form.new(note: "Rush order")
  form.locale    # => "en"
  form.currency  # => "USD"
end
```

Explicit values always win over ambient context. Context references must point to declared fields (or attributes).

## Reading and writing

```ruby
form = Employee::Form.new(name: "Alice", department: "Engineering")

form.name               # => "Alice"
form.department         # => "Engineering"
form.name = "Bob"       # direct setter
form.assign_attributes(department: "Product")  # bulk update
```

## String keys

Forms accept both symbol and string keys – handy when working with ActionController params:

```ruby
form = Employee::Form.new("name" => "Alice", "department" => "Engineering")
form.name  # => "Alice"
```
