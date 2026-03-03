# Validation

`Dex::Form` includes the full `ActiveModel::Validations` DSL – the same one you use in Rails models.

## Standard validators

```ruby
class RegistrationForm < Dex::Form
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
form = RegistrationForm.new(email: "", name: "A")

form.valid?    # => false
form.invalid?  # => true

form.errors[:email]         # => ["can't be blank", "is invalid"]
form.errors[:name]          # => ["is too short (minimum is 2 characters)"]
form.errors.full_messages   # => ["Email can't be blank", "Email is invalid", ...]
```

## Custom validators

Use `validate` with a method name for cross-field checks:

```ruby
class BookingForm < Dex::Form
  attribute :check_in, :date
  attribute :check_out, :date

  validates :check_in, :check_out, presence: true
  validate :check_out_after_check_in

  private

  def check_out_after_check_in
    return if check_in.blank? || check_out.blank?
    errors.add(:check_out, "must be after check-in") if check_out <= check_in
  end
end
```

## Validation contexts

```ruby
class ArticleForm < Dex::Form
  attribute :title, :string
  attribute :body, :string

  validates :title, presence: true
  validates :body, presence: true, on: :publish
end

form = ArticleForm.new(title: "Draft")
form.valid?           # => true (body not required)
form.valid?(:publish) # => false (body required for publishing)
```

## Uniqueness

`Dex::Form` ships a `UniquenessValidator` that checks values against the database:

```ruby
class RegistrationForm < Dex::Form
  model User

  attribute :email, :string
  validates :email, uniqueness: true
end
```

The validator queries the model declared with `model` to check for duplicates. When the form has a `record` (editing an existing entry), that record is automatically excluded from the check.

### Options

| Option | Description | Example |
|--------|-------------|---------|
| `model:` | Explicit model class (overrides `model` DSL) | `uniqueness: { model: User }` |
| `attribute:` | Column name when it differs from the form attribute | `uniqueness: { attribute: :email }` |
| `scope:` | Scope the check to other attributes | `uniqueness: { scope: :tenant_id }` |
| `case_sensitive:` | Case-insensitive comparison (uses SQL `LOWER()`) | `uniqueness: { case_sensitive: false }` |
| `conditions:` | Additional query constraints | `uniqueness: { conditions: -> { where(active: true) } }` |
| `message:` | Custom error message | `uniqueness: { message: "already registered" }` |

### Model resolution

The validator figures out which model to query in this order:

1. The `model:` option on the validator itself
2. The class-level `model` declaration
3. Inferred from the form class name – `RegistrationForm` → `Registration`

If none of these resolve to a model, the validation silently passes.

### Scoped uniqueness

```ruby
class InviteForm < Dex::Form
  model Invitation

  attribute :email, :string
  attribute :team_id, :integer

  validates :email, uniqueness: { scope: :team_id }
end
```

### Case-insensitive

```ruby
validates :email, uniqueness: { case_sensitive: false }
```

When the model supports Arel (ActiveRecord models do), this generates a `LOWER(column) = LOWER(value)` query for proper database-level comparison.

## ValidationError

For cases where you want to raise on invalid forms:

```ruby
form = RegistrationForm.new(email: "")
form.valid?

error = Dex::Form::ValidationError.new(form)
error.message  # => "Validation failed: Email can't be blank"
error.form     # => the form instance
```
