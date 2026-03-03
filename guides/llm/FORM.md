# Dex::Form — LLM Reference

Copy this to your app's forms directory (e.g., `app/forms/AGENTS.md`) so coding agents know the full API when implementing and testing forms.

---

## Reference Form

All examples below build on this form unless noted otherwise:

```ruby
class OnboardingForm < Dex::Form
  model User

  attribute :first_name, :string
  attribute :last_name, :string
  attribute :email, :string
  attribute :department, :string
  attribute :start_date, :date

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  validates :email, presence: true, uniqueness: true
  validates :first_name, :last_name, :department, presence: true
  validates :start_date, presence: true

  nested_one :address do
    attribute :street, :string
    attribute :city, :string
    attribute :postal_code, :string
    attribute :country, :string

    validates :street, :city, :country, presence: true
  end

  nested_many :documents do
    attribute :document_type, :string
    attribute :document_number, :string

    validates :document_type, :document_number, presence: true
  end
end
```

---

## Defining Forms

Forms use ActiveModel under the hood. Attributes are declared with `attribute` (same as ActiveModel::Attributes).

```ruby
class ProfileForm < Dex::Form
  attribute :name, :string
  attribute :age, :integer
  attribute :bio, :string
  attribute :active, :boolean, default: true
  attribute :born_on, :date
end
```

### Available types

`:string`, `:integer`, `:float`, `:decimal`, `:boolean`, `:date`, `:datetime`, `:time`.

### `model(klass)`

Declares the backing model class. Used by:
- `model_name` — delegates to model for Rails routing (`form_with model: @form`)
- `validates :attr, uniqueness: true` — queries this model
- `persisted?` — delegates to `record`

```ruby
class UserForm < Dex::Form
  model User
end
```

Optional. Multi-model forms often skip it.

---

## Normalization

Uses Rails' `normalizes` (Rails 7.1+). Applied on every assignment.

```ruby
normalizes :email, with: -> { _1&.strip&.downcase.presence }
normalizes :phone, with: -> { _1&.gsub(/\D/, "").presence }
normalizes :name, :email, with: -> { _1&.strip.presence }   # multiple attrs
```

---

## Validation

Full ActiveModel validation DSL:

```ruby
validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
validates :name, presence: true, length: { minimum: 2, maximum: 100 }
validates :role, inclusion: { in: %w[admin user] }
validates :email, uniqueness: true                    # checks database
validate :custom_validation_method
```

```ruby
form.valid?              # => true/false
form.invalid?            # => true/false
form.errors              # => ActiveModel::Errors
form.errors[:email]      # => ["can't be blank"]
form.errors.full_messages # => ["Email can't be blank"]
```

### ValidationError

```ruby
error = Dex::Form::ValidationError.new(form)
error.message  # => "Validation failed: Email can't be blank, Name can't be blank"
error.form     # => the form instance
```

---

## Nested Forms

### `nested_one`

One-to-one nested form. Automatically coerces Hash input.

```ruby
nested_one :address do
  attribute :street, :string
  attribute :city, :string
  validates :street, :city, presence: true
end
```

```ruby
form = MyForm.new(address: { street: "123 Main", city: "NYC" })
form.address.street         # => "123 Main"
form.address.class          # => MyForm::Address (auto-generated)

form.build_address(street: "456 Oak")  # build new nested
form.address_attributes = { city: "Boston" }  # Rails compat setter
```

Default: initialized as empty form when not provided.

### `nested_many`

One-to-many nested form. Handles Array, Rails numbered Hash, and `_destroy`.

```ruby
nested_many :documents do
  attribute :document_type, :string
  attribute :document_number, :string
  validates :document_type, :document_number, presence: true
end
```

```ruby
# Array of hashes
form = MyForm.new(documents: [
  { document_type: "passport", document_number: "AB123" },
  { document_type: "visa", document_number: "CD456" }
])

# Rails numbered hash format (from form submissions)
form = MyForm.new(documents: {
  "0" => { document_type: "passport", document_number: "AB123" },
  "1" => { document_type: "visa", document_number: "CD456" }
})

# _destroy support
form = MyForm.new(documents: [
  { document_type: "passport", document_number: "AB123" },
  { document_type: "visa", document_number: "CD456", _destroy: "1" }  # filtered out
])
form.documents.size  # => 1

form.build_document(document_type: "id_card")  # append new
form.documents_attributes = { "0" => { document_type: "id_card" } }  # Rails compat setter
```

Default: initialized as `[]` when not provided.

### `class_name` option

Override the auto-generated constant name:

```ruby
nested_one :address, class_name: "HomeAddress" do
  attribute :street, :string
end
# Creates MyForm::HomeAddress instead of MyForm::Address
```

### Validation propagation

Nested errors bubble up with prefixed attribute names:

```ruby
form.valid?
form.errors[:"address.street"]         # => ["can't be blank"]
form.errors[:"documents[0].doc_type"]  # => ["can't be blank"]
form.errors.full_messages
# => ["Address street can't be blank", "Documents[0] doc type can't be blank"]
```

---

## Uniqueness Validation

Checks uniqueness against the database.

```ruby
validates :email, uniqueness: true
```

### Options

| Option | Description | Example |
|--------|-------------|---------|
| `model:` | Explicit model class | `uniqueness: { model: User }` |
| `attribute:` | Column name if different | `uniqueness: { attribute: :email }` |
| `scope:` | Scoped uniqueness | `uniqueness: { scope: :tenant_id }` |
| `case_sensitive:` | Case-insensitive check | `uniqueness: { case_sensitive: false }` |
| `conditions:` | Extra query conditions | `uniqueness: { conditions: -> { where(active: true) } }` |
| `message:` | Custom error message | `uniqueness: { message: "already registered" }` |

### Model resolution

1. `options[:model]` (explicit)
2. `form.class._model_class` (from `model` DSL)
3. Infer from class name: `RegistrationForm` → `Registration`
4. If none found, validation is a no-op

### Record exclusion

When `form.record` is persisted, the current record is excluded from the uniqueness check (for updates).

---

## Record Binding

Use `with_record` to associate a model instance with the form. This is the recommended approach in controllers – it keeps the record separate from user-submitted params.

```ruby
# Chainable — preferred in controllers
form = OnboardingForm.new(params.require(:onboarding)).with_record(user)

# Constructor hash — convenient in plain Ruby / tests
form = OnboardingForm.new(name: "Alice", record: user)
```

```ruby
form.record      # => the ActiveRecord instance (or nil)
form.persisted?  # => true if record is present and persisted
form.to_key      # => delegates to record (for URL generation)
form.to_param    # => delegates to record
```

`record` is read-only after construction — there is no public `record=` setter.

---

## Serialization

```ruby
form.to_h
# => {
#   first_name: "Alice", last_name: "Smith", email: "alice@example.com",
#   address: { street: "123 Main", city: "NYC", postal_code: nil, country: nil },
#   documents: [{ document_type: "passport", document_number: "AB123" }]
# }

form.to_hash  # alias for to_h
```

---

## Rails Integration

### `form_with`

```erb
<%= form_with model: @form, url: onboarding_path do |f| %>
  <%= f.text_field :first_name %>
  <%= f.text_field :last_name %>
  <%= f.email_field :email %>

  <%= f.fields_for :address do |a| %>
    <%= a.text_field :street %>
    <%= a.text_field :city %>
  <% end %>

  <%= f.fields_for :documents do |d| %>
    <%= d.text_field :document_type %>
    <%= d.text_field :document_number %>
    <%= d.hidden_field :_destroy %>
  <% end %>

  <%= f.submit %>
<% end %>
```

### Controller pattern

Strong parameters (`permit`) are not required — the form's attribute declarations are the whitelist. Just `require` the top-level key:

```ruby
class OnboardingController < ApplicationController
  def new
    @form = OnboardingForm.new
  end

  def create
    @form = OnboardingForm.new(params.require(:onboarding))

    if @form.save
      redirect_to dashboard_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @form = OnboardingForm.for(current_user)
  end

  def update
    @form = OnboardingForm.new(params.require(:onboarding)).with_record(current_user)

    if @form.save
      redirect_to dashboard_path
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
```

---

## Suggested Conventions

Dex::Form handles data holding, normalization, and validation. Persistence and record mapping are user-defined. These conventions are recommended:

### `.for(record)` — load from record

```ruby
class OnboardingForm < Dex::Form
  def self.for(user)
    employee = user.employee

    new(
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      department: employee.department,
      start_date: employee.start_date,
      address: {
        street: employee.address.street, city: employee.address.city,
        postal_code: employee.address.postal_code, country: employee.address.country
      },
      documents: employee.documents.map { |d|
        { document_type: d.document_type, document_number: d.document_number }
      }
    ).with_record(user)
  end
end
```

### `#save` — persist via Operation

```ruby
class OnboardingForm < Dex::Form
  def save
    return false unless valid?

    case operation.safe.call
    in Ok then true
    in Err => e then errors.add(:base, e.message) and false
    end
  end

  private

  def operation
    Onboarding::Upsert.new(
      user: record, first_name:, last_name:, email:,
      department:, start_date:,
      address: address.to_h,
      documents: documents.map(&:to_h)
    )
  end
end
```

---

## Complete Example

A form spanning User, Employee, and Address — the core reason form objects exist.

```ruby
class OnboardingForm < Dex::Form
  attribute :first_name, :string
  attribute :last_name, :string
  attribute :email, :string
  attribute :department, :string
  attribute :position, :string
  attribute :start_date, :date

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  validates :email, presence: true, uniqueness: { model: User }
  validates :first_name, :last_name, :department, :position, presence: true
  validates :start_date, presence: true

  nested_one :address do
    attribute :street, :string
    attribute :city, :string
    attribute :postal_code, :string
    attribute :country, :string

    validates :street, :city, :country, presence: true
  end

  nested_many :documents do
    attribute :document_type, :string
    attribute :document_number, :string

    validates :document_type, :document_number, presence: true
  end

  def self.for(user)
    employee = user.employee

    new(
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      department: employee.department,
      position: employee.position,
      start_date: employee.start_date,
      address: {
        street: employee.address.street, city: employee.address.city,
        postal_code: employee.address.postal_code, country: employee.address.country
      },
      documents: employee.documents.map { |d|
        { document_type: d.document_type, document_number: d.document_number }
      }
    ).with_record(user)
  end

  def save
    return false unless valid?

    case operation.safe.call
    in Ok then true
    in Err => e then errors.add(:base, e.message) and false
    end
  end

  private

  def operation
    Onboarding::Upsert.new(
      user: record, first_name:, last_name:, email:,
      department:, position:, start_date:,
      address: address.to_h,
      documents: documents.map(&:to_h)
    )
  end
end
```

---

## Testing

Forms are standard ActiveModel objects. Test them with plain Minitest — no special helpers needed.

```ruby
class OnboardingFormTest < Minitest::Test
  def test_validates_required_fields
    form = OnboardingForm.new
    assert form.invalid?
    assert form.errors[:email].any?
    assert form.errors[:first_name].any?
  end

  def test_normalizes_email
    form = OnboardingForm.new(email: "  ALICE@EXAMPLE.COM  ")
    assert_equal "alice@example.com", form.email
  end

  def test_nested_validation_propagation
    form = OnboardingForm.new(
      first_name: "Alice", last_name: "Smith",
      email: "alice@example.com", department: "Eng",
      position: "Developer", start_date: Date.today,
      address: { street: "", city: "", country: "" }
    )
    assert form.invalid?
    assert form.errors[:"address.street"].any?
  end

  def test_to_h_serialization
    form = OnboardingForm.new(
      first_name: "Alice", email: "alice@example.com",
      address: { street: "123 Main", city: "NYC" }
    )
    h = form.to_h
    assert_equal "Alice", h[:first_name]
    assert_equal "123 Main", h[:address][:street]
  end
end
```
