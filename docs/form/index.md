---
description: Build Rails form objects with Dex::Form – typed attributes, normalization, validations, nested forms, and form builder compatibility.
---

# Dex::Form

Form objects that handle the messy reality of user input – typed attributes, normalization, validation, and nested forms that work with Rails form builders out of the box.

## Quick Start

```ruby
class Employee::Form < Dex::Form
  attribute :email, :string
  attribute :first_name, :string
  attribute :last_name, :string

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  validates :email, :first_name, :last_name, presence: true

  nested_one :address do
    attribute :street, :string
    attribute :city, :string
    validates :street, :city, presence: true
  end
end
```

```ruby
form = Employee::Form.new(
  email: "  ALICE@EXAMPLE.COM  ",
  first_name: "Alice",
  last_name: "Smith",
  address: { street: "123 Main", city: "NYC" }
)

form.email        # => "alice@example.com" (normalized)
form.valid?       # => true
form.to_h         # => { email: "alice@example.com", first_name: "Alice", ... }
```

## Why form objects?

Rails form builders work great when a form maps directly to a single model. But real forms rarely do:

- An onboarding form might touch Employee, Department, and Position – three separate models
- A checkout form collects payment details, shipping info, and order notes – none of which map 1:1 to a model
- An employee form needs an email uniqueness check but doesn't want `accepts_nested_attributes_for` gymnastics

`Dex::Form` gives you a clean place to define the shape of your form, validate it, and serialize it – without coupling to any particular model structure.

## What you get

- **ActiveModel attributes** with type casting and defaults
- **Normalization** – strip, downcase, and transform on every assignment
- **Full validation DSL** – everything from `ActiveModel::Validations`, plus database uniqueness checks
- **Nested forms** – `nested_one` and `nested_many` with automatic Hash coercion, `_destroy` support, and error propagation
- **Rails compatibility** – works with `form_with`, `fields_for`, and nested attributes
- **No strong parameters required** – the form's attribute declarations are the whitelist
- **Serialization** – `to_h` recursively serializes the entire form tree

## What you don't get (on purpose)

`Dex::Form` handles holding, normalizing, and validating form data. It does not handle persistence or record-to-form mapping – those are your responsibility, and the [Conventions](/form/conventions) page shows clean patterns for both.

## What's next

- [Attributes & Normalization](/form/attributes) – defining inputs and transforming values
- [Validation](/form/validation) – presence, format, uniqueness, and custom validators
- [Nested Forms](/form/nesting) – `nested_one`, `nested_many`, `_destroy`, error propagation
- [Rails Integration](/form/rails) – `form_with`, `fields_for`, controllers
- [Conventions](/form/conventions) – `.for`, `#save`, and working with `Dex::Operation`
