---
description: Dex::Form nested forms — nested_one and nested_many with automatic coercion, validation propagation, and _destroy support.
---

# Nested Forms

Forms often contain groups of related fields – an address block, a list of line items, a set of emergency contacts. `nested_one` and `nested_many` let you define these as nested form objects with their own attributes, validations, and error reporting.

## nested_one

Defines a single nested form:

```ruby
class Order::Form < Dex::Form
  attribute :notes, :string

  nested_one :shipping_address do
    attribute :street, :string
    attribute :city, :string
    attribute :zip, :string

    validates :street, :city, :zip, presence: true
  end
end
```

```ruby
form = Order::Form.new(
  notes: "Leave at door",
  shipping_address: { street: "123 Main", city: "NYC", zip: "10001" }
)

form.shipping_address.street  # => "123 Main"
form.shipping_address.class   # => Order::Form::ShippingAddress
```

### Hash coercion

Pass a Hash and it gets automatically converted to the nested form:

```ruby
form.shipping_address = { street: "456 Oak", city: "LA", zip: "90001" }
form.shipping_address.city  # => "LA"
```

### Default initialization

When you don't provide a nested_one value, it initializes as an empty form:

```ruby
form = Order::Form.new
form.shipping_address        # => an empty ShippingAddress (not nil)
form.shipping_address.street # => nil
```

### Building nested forms

```ruby
form.build_shipping_address(street: "789 Pine", city: "SF")
form.shipping_address.city  # => "SF"
```

## nested_many

Defines a collection of nested forms:

```ruby
class Order::InvoiceForm < Dex::Form
  attribute :number, :string

  nested_many :line_items do
    attribute :description, :string
    attribute :quantity, :integer
    attribute :price, :decimal

    validates :description, :quantity, :price, presence: true
  end
end
```

```ruby
form = Order::InvoiceForm.new(line_items: [
  { description: "Widget", quantity: 2, price: "9.99" },
  { description: "Gadget", quantity: 1, price: "24.99" }
])

form.line_items.size              # => 2
form.line_items[0].description    # => "Widget"
form.line_items[0].price          # => #<BigDecimal: 9.99>
```

### Default initialization

When you don't provide a nested_many value, it initializes as an empty array:

```ruby
form = Order::InvoiceForm.new
form.line_items  # => []
```

### Building items

```ruby
form.build_line_item(description: "New item", quantity: 1, price: "5.00")
form.line_items.size  # => 1
```

### Rails numbered hash format

Rails form builders submit nested collections as numbered hashes. This is handled automatically:

```ruby
form = Order::InvoiceForm.new(line_items: {
  "0" => { description: "Widget", quantity: "2", price: "9.99" },
  "1" => { description: "Gadget", quantity: "1", price: "24.99" }
})
form.line_items.size  # => 2
```

### _destroy support

Items with `_destroy` set to a truthy value are filtered out during coercion:

```ruby
form = Order::InvoiceForm.new(line_items: [
  { description: "Keep this", quantity: 1, price: "10.00" },
  { description: "Remove this", quantity: 1, price: "5.00", _destroy: "1" }
])
form.line_items.size  # => 1
```

Truthy values include `"1"`, `"true"`, and `true` – the same values Rails considers truthy for `_destroy`.

## Validation propagation

Invalid nested forms bubble their errors up to the parent with prefixed attribute names:

```ruby
form = Order::Form.new(shipping_address: { street: "", city: "", zip: "" })
form.valid?  # => false

form.errors[:"shipping_address.street"]  # => ["can't be blank"]
form.errors[:"shipping_address.city"]    # => ["can't be blank"]
```

For nested_many, errors include the index:

```ruby
form = Order::InvoiceForm.new(line_items: [
  { description: "Good", quantity: 1, price: "10.00" },
  { description: "", quantity: nil, price: nil }
])
form.valid?  # => false

form.errors[:"line_items[1].description"]  # => ["can't be blank"]
form.errors[:"line_items[1].quantity"]     # => ["can't be blank"]
```

## Constant naming

`nested_one :address` creates a constant `Address` on the parent form class. `nested_many :line_items` creates `LineItem` (singularized). Override with `class_name:`:

```ruby
nested_one :address, class_name: "HomeAddress" do
  attribute :street, :string
end
# Creates Order::Form::HomeAddress instead of Order::Form::Address
```

## Serialization

`to_h` recursively serializes nested forms:

```ruby
form.to_h
# => {
#   number: "INV-001",
#   line_items: [
#     { description: "Widget", quantity: 2, price: #<BigDecimal: 9.99> },
#     { description: "Gadget", quantity: 1, price: #<BigDecimal: 24.99> }
#   ]
# }
```

The class-level export APIs recurse too:

```ruby
Order::Form.to_h
# => {
#   fields: { ... },
#   nested: {
#     shipping_address: {
#       type: :one,
#       fields: { ... },
#       nested: { ... }
#     }
#   }
# }

Dex::Form.export(format: :hash)
# => [{ name: "Order::Form", fields: { ... }, nested: { ... } }]
```

`Dex::Form.export` includes top-level named forms only. Nested helper classes stay inside the parent form's export.

## Inheritance

Nested definitions are safely inherited. Adding nested forms to a child class doesn't affect the parent:

```ruby
class BaseForm < Dex::Form
  nested_one :address do
    attribute :street, :string
  end
end

class ExtendedForm < BaseForm
  nested_one :billing do
    attribute :card_number, :string
  end
end

BaseForm._nested_ones.keys     # => [:address]
ExtendedForm._nested_ones.keys # => [:address, :billing]
```
