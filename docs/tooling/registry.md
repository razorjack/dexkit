---
description: Browse the class registry, add descriptions, and export contracts as hashes or JSON Schema across all dexkit patterns.
---

# Registry & Export

dexkit tracks every named `Dex::Operation`, `Dex::Event`, and `Dex::Event::Handler` subclass in a registry. Combined with the `description` DSL and export methods, this gives you programmatic access to your entire API surface – useful for admin panels, documentation generators, and LLM tooling.

## Description

Add a human-readable description to any operation or event:

```ruby
class Order::Place < Dex::Operation
  description "Place a new order for a customer"

  prop :customer, _Ref(Customer)
  prop :product, _Ref(Product)
  prop :quantity, _Integer(1..)

  def perform
    # ...
  end
end
```

Descriptions are inherited – a child class without its own description uses the parent's.

### Property descriptions

Add `desc:` to individual props for per-field documentation:

```ruby
class Order::Place < Dex::Operation
  description "Place a new order for a customer"

  prop :customer, _Ref(Customer), desc: "The customer placing the order"
  prop :product, _Ref(Product), desc: "Product to order"
  prop :quantity, _Integer(1..), desc: "Number of units (minimum 1)"
  prop? :note, String, desc: "Optional note for the warehouse"

  def perform
    # ...
  end
end
```

`desc:` works on both `prop` and `prop?`, on Operations and Events alike. Descriptions appear in `contract.to_h`, JSON Schema output, and LLM tool definitions.

## Registry

Every named subclass of `Dex::Operation`, `Dex::Event`, and `Dex::Event::Handler` is automatically registered:

```ruby
Dex::Operation.registry
# => #<Set: {Order::Place, Order::Cancel, Employee::Onboard, ...}>

Dex::Event.registry
# => #<Set: {Order::Placed, Order::Cancelled, ...}>

Dex::Event::Handler.registry
# => #<Set: {NotifyWarehouse, SendConfirmation, ...}>
```

Each call returns a frozen Set. Anonymous classes (created with `Class.new`) are excluded. Stale classes that are no longer reachable after code reload are also filtered out automatically.

### Deregistering

Remove a class from the registry if needed – useful for test cleanup or deprecation:

```ruby
Dex::Operation.deregister(Order::LegacyPlace)
```

To empty a registry entirely:

```ruby
Dex::Operation.clear!
```

### Zeitwerk compatibility

In a Rails app with Zeitwerk autoloading, classes are only registered once they're loaded. The registry reflects what's currently in memory – it's reload-safe, so stale class objects from previous loads are automatically excluded. If you need a complete picture (for export, admin panels, etc.), eager-load first:

```ruby
Rails.application.eager_load!
Dex::Operation.registry  # now contains everything
```

The `dex:export` rake task does this automatically.

## Exporting contracts

### Single operation

`contract.to_h` returns a rich Hash describing the operation's full interface:

```ruby
Order::Place.contract.to_h
# => {
#   name: "Order::Place",
#   description: "Place a new order for a customer",
#   params: {
#     customer: { type: "Ref(Customer)", required: true, desc: "The customer placing the order" },
#     product:  { type: "Ref(Product)", required: true, desc: "Product to order" },
#     quantity: { type: "Integer(1..)", required: true, desc: "Number of units (minimum 1)" },
#     note:     { type: "Nilable(String)", required: false, desc: "Optional note for the warehouse" }
#   },
#   success: "Ref(Order)",
#   errors: [:out_of_stock],
#   guards: [{ name: :product_available, message: "Product must be in stock" }],
#   context: { customer: :current_customer },
#   pipeline: [:trace, :result, :guard, :once, :lock, :record, :transaction, :rescue, :callback],
#   settings: {
#     record: { enabled: true, params: true, result: true },
#     transaction: { enabled: true },
#     once: { defined: false }
#   }
# }
```

### JSON Schema

Generate JSON Schema (Draft 2020-12) for specific sections:

```ruby
Order::Place.contract.to_json_schema(section: :params)
# => {
#   "$schema": "https://json-schema.org/draft/2020-12/schema",
#   type: "object",
#   title: "Order::Place",
#   description: "Place a new order for a customer",
#   properties: {
#     "customer" => { type: "string", description: "Customer ID" },
#     "product"  => { type: "string", description: "Product ID" },
#     "quantity" => { type: "integer", minimum: 1, description: "Number of units (minimum 1)" },
#     "note"     => { oneOf: [{ type: "string" }, { type: "null" }], description: "Optional note..." }
#   },
#   required: ["customer", "product", "quantity"],
#   additionalProperties: false
# }
```

Available sections:

| Section | What it describes |
|---|---|
| `:params` | Input parameters (default) |
| `:success` | Success return type |
| `:errors` | Error code schemas |
| `:full` | All three combined |

### Type serialization

Types are serialized as readable strings in `to_h` and as JSON Schema types in `to_json_schema`:

| Ruby type | String | JSON Schema |
|---|---|---|
| `String` | `"String"` | `{ type: "string" }` |
| `Integer` | `"Integer"` | `{ type: "integer" }` |
| `_Integer(1..)` | `"Integer(1..)"` | `{ type: "integer", minimum: 1 }` |
| `_Ref(Order)` | `"Ref(Order)"` | `{ type: "string", description: "Order ID" }` |
| `_Nilable(String)` | `"Nilable(String)"` | `{ oneOf: [{ type: "string" }, { type: "null" }] }` |
| `_Array(String)` | `"Array(String)"` | `{ type: "array", items: { type: "string" } }` |
| `_Union("USD", "EUR")` | `"Union(\"USD\", \"EUR\")"` | `{ enum: ["USD", "EUR"] }` |
| `BigDecimal` | `"BigDecimal"` | `{ type: "string", pattern: "..." }` |

### Events

Events have `to_h` and `to_json_schema` as class methods (they don't have contracts):

```ruby
Order::Placed.to_h
# => {
#   name: "Order::Placed",
#   description: "Fired when an order is successfully placed",
#   props: {
#     order_id: { type: "Integer", required: true },
#     total:    { type: "BigDecimal", required: true }
#   }
# }

Order::Placed.to_json_schema
# => { "$schema": "...", type: "object", title: "Order::Placed", ... }
```

### Handlers

```ruby
NotifyWarehouse.to_h
# => {
#   name: "NotifyWarehouse",
#   events: ["Order::Placed"],
#   retries: 3,
#   transaction: false,
#   pipeline: [:transaction, :callback]
# }
```

## Bulk export

Export all registered classes at once:

```ruby
Dex::Operation.export(format: :hash)
# => [{ name: "Employee::Onboard", ... }, { name: "Order::Place", ... }, ...]

Dex::Operation.export(format: :json_schema, section: :params)
# => [{ "$schema": "...", title: "Employee::Onboard", ... }, ...]

Dex::Event.export(format: :hash)
# => [{ name: "Order::Placed", ... }, ...]

Dex::Event::Handler.export(format: :hash)
# => [{ name: "NotifyWarehouse", ... }, ...]
```

Results are sorted by class name.

## Rake task

In Rails apps, a `dex:export` task is available automatically via the Railtie:

```bash
# Export all operations as hash (default)
rake dex:export

# Export as JSON Schema
rake dex:export FORMAT=json_schema

# Export events
rake dex:export SECTION=events

# Export handlers
rake dex:export SECTION=handlers

# Write to file
rake dex:export FILE=tmp/operations.json
```

| Env var | Values | Default |
|---|---|---|
| `FORMAT` | `hash`, `json_schema` | `hash` |
| `SECTION` | `operations`, `events`, `handlers` | `operations` |
| `FILE` | File path | stdout |

The task calls `Rails.application.eager_load!` before exporting, so all classes are registered regardless of autoloading state.