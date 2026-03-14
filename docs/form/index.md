---
description: Dex::Form — form objects with typed fields, validation, nested forms, and normalization that work with Rails form builders and export to JSON Schema.
---

# Dex::Form

Form objects that handle the messy reality of user input – typed fields, normalization, validation, and nested forms that work with Rails form builders out of the box.

## Quick Start

```ruby
class Employee::Form < Dex::Form
  description "Employee onboarding form"

  field :email, :string
  field :first_name, :string
  field :last_name, :string
  field :locale, :string
  field? :notes, :string

  context :locale

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  nested_one :address do
    field :street, :string
    field :city, :string
    field? :apartment, :string
  end
end
```

```ruby
Dex.with_context(locale: "en") do
  form = Employee::Form.new(
    email: "  ALICE@EXAMPLE.COM  ",
    first_name: "Alice",
    last_name: "Smith",
    address: { street: "123 Main", city: "NYC" }
  )

  form.email        # => "alice@example.com" (normalized)
  form.locale       # => "en" (from ambient context)
  form.valid?       # => true (required fields auto-validated)
  form.to_h         # => { email: "alice@example.com", first_name: "Alice", ... }
end

Employee::Form.to_json_schema  # => { type: "object", properties: { ... }, required: [...] }
```

## Why `field`, not `prop`?

Operation and Event use `prop` backed by Literal – a strict type system that raises immediately if you pass the wrong type. That's correct for internal boundaries where data should already be clean.

Forms are different. A form's job is to accept garbage. A user types `"abc"` into an age field, submits a blank email, picks an invalid date – and the form must hold all of it, validate it, and display it back with error messages. Garbage in, helpful errors out.

That's why Form uses `field` backed by ActiveModel's attribute API instead of Literal props. ActiveModel coerces `"abc"` to `nil` for an integer field and lets validations explain the problem. Literal would raise a `TypeError` before you ever got the chance to show a helpful error message.

Same family, different job. Operations enforce. Forms forgive.

## Why form objects?

Rails form builders work great when a form maps directly to a single model. But real forms rarely do:

- An onboarding form might touch Employee, Department, and Position – three separate models
- A checkout form collects payment details, shipping info, and order notes – none of which map 1:1 to a model
- An employee form needs an email uniqueness check but doesn't want `accepts_nested_attributes_for` gymnastics

`Dex::Form` gives you a clean place to define the shape of your form, validate it, and serialize it – without coupling to any particular model structure.

## What you get

- **`field` / `field?`** – required and optional fields with auto-presence validation and metadata tracking; unconditional presence validators deduplicate cleanly
- **Normalization** – strip, downcase, and transform on every assignment
- **Full validation DSL** – everything from `ActiveModel::Validations`, plus database uniqueness checks
- **Nested forms** – `nested_one` and `nested_many` with automatic Hash coercion, `_destroy` support, and error propagation
- **Ambient context** – auto-fill fields from `Dex.context`, same DSL as Operation and Event
- **Registry & Export** – `description`, `to_json_schema`, `to_h` (class-level), and `Dex::Form.export` – same ecosystem as Operation and Event, with recursive nested schemas
- **Rails compatibility** – works with `form_with`, `fields_for`, and nested attributes
- **No strong parameters required** – the form's field declarations are the whitelist
- **Serialization** – `to_h` (instance-level) recursively serializes the entire form tree

## What you don't get (on purpose)

`Dex::Form` handles holding, normalizing, and validating form data. It does not handle persistence or record-to-form mapping – those are your responsibility, and the [Conventions](/form/conventions) page shows clean patterns for both.

## What's next

- [Fields & Normalization](/form/attributes) – declaring fields, type casting, and transforming values
- [Validation](/form/validation) – presence, format, uniqueness, and custom validators
- [Nested Forms](/form/nesting) – `nested_one`, `nested_many`, `_destroy`, error propagation
- [Rails Integration](/form/rails) – `form_with`, `fields_for`, controllers
- [Conventions](/form/conventions) – `.for`, `#save`, and working with `Dex::Operation`
