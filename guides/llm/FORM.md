# Dex::Form — LLM Reference

Install with `rake dex:guides` or copy manually to `app/forms/AGENTS.md`.

---

## Reference Form

All examples below build on this form unless noted otherwise:

```ruby
class OnboardingForm < Dex::Form
  description "Employee onboarding"
  model User

  field :first_name, :string
  field :last_name, :string
  field :email, :string
  field :department, :string
  field :start_date, :date
  field :locale, :string
  field? :notes, :string

  context :locale

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  validates :email, uniqueness: true

  nested_one :address do
    field :street, :string
    field :city, :string
    field :postal_code, :string
    field :country, :string
    field? :apartment, :string
  end

  nested_many :documents do
    field :document_type, :string
    field :document_number, :string
  end
end
```

---

## Declaring Fields

### `field` — required

Declares a required field. Auto-adds presence validation. Unconditional `validates :attr, presence: true` deduplicates with it; scoped or conditional presence validators do not make the field optional outside those cases.

```ruby
field :name, :string
field :email, :string, desc: "Work email"
field :currency, :string, default: "USD"
```

### `field?` — optional

Declares an optional field. Defaults to `nil` unless overridden.

```ruby
field? :notes, :string
field? :priority, :integer, default: 0
```

### Options

| Option | Description |
|--------|-------------|
| `desc:` | Human-readable description (for introspection and JSON Schema) |
| `default:` | Default value (forwarded to ActiveModel) |

### Available types

`:string`, `:integer`, `:float`, `:decimal`, `:boolean`, `:date`, `:datetime`, `:time`.

### `attribute` escape hatch

Raw ActiveModel `attribute` is still available. Not tracked in field registry, no auto-presence, not in exports.

### Boolean fields

`field :active, :boolean` checks for `nil` (not `blank?`), so `false` is valid.

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

Full ActiveModel validation DSL. Required fields auto-validate presence — no need to add `validates :name, presence: true` when using `field :name, :string`.

```ruby
validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
validates :name, length: { minimum: 2, maximum: 100 }
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

### Contextual requirements

Use `field?` with an explicit validation context:

```ruby
field? :published_at, :datetime
validates :published_at, presence: true, on: :publish
```

### ValidationError

```ruby
error = Dex::Form::ValidationError.new(form)
error.message  # => "Validation failed: Email can't be blank, Name can't be blank"
error.form     # => the form instance
```

---

## Ambient Context

Auto-fill fields from `Dex.context` – same DSL as Operation and Event:

```ruby
class Order::Form < Dex::Form
  field :locale, :string
  field :currency, :string

  context :locale                       # shorthand: field name = context key
  context currency: :default_currency   # explicit: field name → context key
end

Dex.with_context(locale: "en", default_currency: "USD") do
  form = Order::Form.new
  form.locale    # => "en"
  form.currency  # => "USD"
end
```

Explicit values always win. Context references must point to declared fields or attributes.

---

## Registry & Export

### Description

```ruby
class OnboardingForm < Dex::Form
  description "Employee onboarding"
end

OnboardingForm.description  # => "Employee onboarding"
```

### Registry

```ruby
Dex::Form.registry  # => #<Set: {OnboardingForm, ...}>
```

### Class-level `to_h`

```ruby
OnboardingForm.to_h
# => {
#   name: "OnboardingForm",
#   description: "Employee onboarding",
#   fields: {
#     first_name: { type: :string, required: true },
#     email: { type: :string, required: true },
#     notes: { type: :string, required: false },
#     ...
#   },
#   nested: {
#     address: { type: :one, fields: { ... }, nested: { ... } },
#     documents: { type: :many, fields: { ... } }
#   }
# }
```

### `to_json_schema`

```ruby
OnboardingForm.to_json_schema
# => {
#   "$schema": "https://json-schema.org/draft/2020-12/schema",
#   type: "object",
#   title: "OnboardingForm",
#   description: "Employee onboarding",
#   properties: { email: { type: "string" }, ... },
#   required: ["first_name", "last_name", "email", ...],
#   additionalProperties: false
# }
```

### Global export

```ruby
Dex::Form.export(format: :json_schema)
# => [{ ... OnboardingForm schema ... }, ...]
```

Bulk export returns top-level named forms only. Nested helper classes generated by `nested_one` and `nested_many` stay embedded in their parent export instead of appearing as separate entries.

---

## Nested Forms

### `nested_one`

One-to-one nested form. Automatically coerces Hash input.

```ruby
nested_one :address do
  field :street, :string
  field :city, :string
  field? :apartment, :string
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
  field :document_type, :string
  field :document_number, :string
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
  field :street, :string
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
| `case_sensitive:` | Case-insensitive check (`LOWER()` on ActiveRecord, case-insensitive regex on Mongoid) | `uniqueness: { case_sensitive: false }` |
| `conditions:` | Extra query conditions | `uniqueness: { conditions: -> { where(active: true) } }` |
| `message:` | Custom error message | `uniqueness: { message: "already registered" }` |

### Model resolution

1. `options[:model]` (explicit)
2. `form.class._model_class` (from `model` DSL)
3. Infer from class name: `RegistrationForm` → `Registration`
4. If none found, validation is a no-op

### Record exclusion

When `form.record` is persisted, the current record is excluded from the uniqueness check (for updates) on both ActiveRecord and Mongoid-backed forms.

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

Strong parameters (`permit`) are not required — the form's field declarations are the whitelist. Just `require` the top-level key:

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
  description "Employee onboarding"

  field :first_name, :string
  field :last_name, :string
  field :email, :string
  field :department, :string
  field :position, :string
  field :start_date, :date
  field :locale, :string
  field? :notes, :string

  context :locale

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  validates :email, uniqueness: { model: User }

  nested_one :address do
    field :street, :string
    field :city, :string
    field :postal_code, :string
    field :country, :string
    field? :apartment, :string
  end

  nested_many :documents do
    field :document_type, :string
    field :document_number, :string
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
  def test_required_fields_validated
    form = OnboardingForm.new
    assert form.invalid?
    assert form.errors[:email].any?
    assert form.errors[:first_name].any?
  end

  def test_optional_fields_allowed_blank
    form = OnboardingForm.new(
      first_name: "Alice", last_name: "Smith",
      email: "alice@example.com", department: "Eng",
      position: "Dev", start_date: Date.today, locale: "en"
    )
    assert form.valid?
    assert_nil form.notes
  end

  def test_normalizes_email
    form = OnboardingForm.new(email: "  ALICE@EXAMPLE.COM  ")
    assert_equal "alice@example.com", form.email
  end

  def test_context_fills_locale
    form = Dex.with_context(locale: "en") { OnboardingForm.new }
    assert_equal "en", form.locale
  end

  def test_nested_validation_propagation
    form = OnboardingForm.new(
      first_name: "Alice", last_name: "Smith",
      email: "alice@example.com", department: "Eng",
      position: "Developer", start_date: Date.today, locale: "en",
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

  def test_json_schema_export
    schema = OnboardingForm.to_json_schema
    assert_equal "object", schema[:type]
    assert_includes schema[:required], "first_name"
    refute_includes schema[:required], "notes"
  end
end
```
