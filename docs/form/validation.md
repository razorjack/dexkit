---
description: Dex::Form validation — ActiveModel validators, custom rules, validation contexts, and database-backed uniqueness checks.
---

# Validation

`Dex::Form` includes the full `ActiveModel::Validations` DSL – the same one you use in Rails models.

## Standard validators

```ruby
class Employee::Form < Dex::Form
  attribute :email, :string
  attribute :name, :string
  attribute :age, :integer
  attribute :role, :string

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :age, numericality: { greater_than: 0 }, allow_nil: true
  validates :role, inclusion: { in: %w[admin user] }
end
```

## Checking validity

```ruby
form = Employee::Form.new(email: "", name: "A")

form.valid?    # => false
form.invalid?  # => true

form.errors[:email]         # => ["can't be blank", "is invalid"]
form.errors[:name]          # => ["is too short (minimum is 2 characters)"]
form.errors.full_messages   # => ["Email can't be blank", "Email is invalid", ...]
```

## Custom validators

Use `validate` with a method name for cross-field checks:

```ruby
class Leave::RequestForm < Dex::Form
  attribute :start_date, :date
  attribute :end_date, :date

  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?
    errors.add(:end_date, "must be after start date") if end_date <= start_date
  end
end
```

## Validation contexts

```ruby
class Product::Form < Dex::Form
  attribute :title, :string
  attribute :description, :string

  validates :title, presence: true
  validates :description, presence: true, on: :launch
end

form = Product::Form.new(title: "Draft")
form.valid?          # => true (description not required)
form.valid?(:launch) # => false (description required for launch)
```

For required fields declared with `field`, Dex keeps the base requirement in place even if you add a scoped presence validator:

```ruby
class Product::Form < Dex::Form
  field :title, :string
  validates :title, presence: true, on: :publish
end

Product::Form.new.valid?          # => false
Product::Form.new.valid?(:publish) # => false
```

If you want a field to be optional until a specific context, declare it with `field?` and add the scoped validator yourself.

## Uniqueness

`Dex::Form` ships a `UniquenessValidator` that checks values against the database:

```ruby
class Employee::Form < Dex::Form
  model Employee

  attribute :email, :string
  validates :email, uniqueness: true
end
```

The validator queries the model declared with `model` to check for duplicates. When the form has a `record` (editing an existing entry), that record is automatically excluded from the check.

### Options

| Option | Description | Example |
|--------|-------------|---------|
| `model:` | Explicit model class (overrides `model` DSL) | `uniqueness: { model: Employee }` |
| `attribute:` | Column name when it differs from the form attribute | `uniqueness: { attribute: :email }` |
| `scope:` | Scope the check to other attributes | `uniqueness: { scope: :tenant_id }` |
| `case_sensitive:` | Case-insensitive comparison (`LOWER()` on ActiveRecord, regex on Mongoid) | `uniqueness: { case_sensitive: false }` |
| `conditions:` | Additional query constraints | `uniqueness: { conditions: -> { where(active: true) } }` |
| `message:` | Custom error message | `uniqueness: { message: "already registered" }` |

### Model resolution

The validator figures out which model to query in this order:

1. The `model:` option on the validator itself
2. The class-level `model` declaration
3. Inferred from the form class name – `Employee::Form` → `Employee`

If none of these resolve to a model, the validation silently passes.

### Scoped uniqueness

```ruby
class Employee::InviteForm < Dex::Form
  model Employee

  attribute :email, :string
  attribute :department_id, :integer

  validates :email, uniqueness: { scope: :department_id }
end
```

### Case-insensitive

```ruby
validates :email, uniqueness: { case_sensitive: false }
```

With ActiveRecord, this generates a `LOWER(column) = LOWER(value)` query. With Mongoid, dexkit uses a case-insensitive exact-match regex.

## ValidationError

For cases where you want to raise on invalid forms:

```ruby
form = Employee::Form.new(email: "")
form.valid?

error = Dex::Form::ValidationError.new(form)
error.message  # => "Validation failed: Email can't be blank"
error.form     # => the form instance
```
