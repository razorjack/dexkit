---
description: Dex::Operation explain — run a side-effect-free preflight check that shows resolved context, guard status, lock keys, and pipeline settings.
---

# Explain

`explain` is a preflight check that resolves context, coerces props, evaluates guards, computes derived keys, and reports effective settings – without executing `perform` or producing any side effects.

## Basic usage

```ruby
info = Order::Place.explain(product: product, customer: customer, quantity: 2)
```

Returns a frozen Hash. The operation is instantiated (context resolved, types validated) but `perform` is never called. No database writes, no jobs enqueued, no side effects.

## Return shape

```ruby
Order::Place.explain(product: product, customer: customer, quantity: 2)
# => {
#   operation: "Order::Place",
#
#   props: { product: #<Product id=7>, customer: #<Customer id=1>, quantity: 2 },
#
#   context: {
#     resolved: { customer: #<Customer id=1> },
#     mappings: { customer: :current_customer },
#     source: { customer: :ambient }
#   },
#
#   guards: {
#     passed: true,
#     results: [
#       { name: :out_of_stock, passed: true },
#       { name: :credit_exceeded, passed: true }
#     ]
#   },
#
#   once: {
#     active: true,
#     key: "Order::Place/product_id=7/quantity=2",
#     status: :fresh,
#     expires_in: nil
#   },
#
#   lock: {
#     active: true,
#     key: "order:7",
#     timeout: nil
#   },
#
#   record: { enabled: true, params: true, result: true },
#
#   transaction: { enabled: true },
#
#   rescue_from: {
#     "Stripe::CardError" => :card_declined,
#     "Stripe::RateLimitError" => :rate_limited
#   },
#
#   callbacks: { before: 1, after: 2, around: 0 },
#
#   pipeline: [:trace, :result, :guard, :once, :lock, :record, :transaction, :rescue, :callback],
#
#   callable: true
# }
```

## Keys

| Key | Source | Description |
|---|---|---|
| `operation` | Core | Class name |
| `description` | Core | Operation description (present only when set via `description` DSL) |
| `error` | Core | Present only when props are invalid; error message string |
| `props` | Core | Resolved and coerced property values |
| `context` | ContextSetup | Resolution details per mapped prop |
| `guards` | GuardWrapper | Per-guard pass/fail results |
| `once` | OnceWrapper | Key, status, expiry |
| `lock` | LockWrapper | Key, timeout |
| `record` | RecordWrapper | Enabled flag, params/result capture settings |
| `transaction` | TransactionWrapper | Enabled flag |
| `rescue_from` | RescueWrapper | Exception-to-code mappings |
| `callbacks` | CallbackWrapper | Callback counts by type |
| `pipeline` | Core | Ordered list of active step names |
| `callable` | Core | Boolean: guards pass and once status is not blocking |

## Context resolution

The `context` section shows how each context-mapped prop was resolved:

```ruby
class Order::Place < Dex::Operation
  prop :product, _Ref(Product)
  prop :customer, _Ref(Customer)
  context customer: :current_customer
end

Dex.with_context(current_customer: admin) do
  info = Order::Place.explain(product: product)
  info[:context][:source][:customer]  # => :ambient
end

info = Order::Place.explain(product: product, customer: customer)
info[:context][:source][:customer]  # => :explicit
```

Source values:
- `:explicit` – passed as a keyword argument
- `:ambient` – filled from `Dex.context`
- `:default` – fell through to the prop's default value
- `:missing` – not provided and no default exists (partial explain only)

## Once status

When `once` is active, the `status` field queries the record backend to determine whether the key already exists:

- `:fresh` – no existing record; would execute `perform`
- `:exists` – record exists; would replay
- `:expired` – record exists but expired; would execute `perform`
- `:pending` – another execution is in-flight with this key
- `:invalid` – the derived key is `nil` (key block returned nil)
- `:misconfigured` – operation is anonymous, record step is missing, or the configured record backend is missing attributes required by `once` (for example `once_key` or `once_key_expires_at`)
- `:unavailable` – no record backend configured

This is a read-only query – no records are created or modified.

## Guard results

Guard results include a `skipped` flag when a guard was skipped due to a failed dependency:

```ruby
info[:guards][:results]
# => [
#   { name: :missing_product, passed: false, message: "Product is required" },
#   { name: :out_of_stock, passed: false, skipped: true }
# ]
```

Failed guards include a `:message` with the reason. Skipped guards have `skipped: true` – their dependency failed, so they were never evaluated.

## Pipeline awareness

`explain` respects pipeline customization. If a step is removed via `pipeline.remove(:guard)`, explain skips guard evaluation and reports `callable: true`. Each section reflects the actual pipeline — if a step isn't there, its section shows the "inactive" state (`{ active: false }`, `{ enabled: false }`, etc.).

## Partial explain

When props are invalid (wrong types, missing required arguments), `explain` returns a partial result instead of raising. Only prop validation errors (`Literal::TypeError`, `ArgumentError`) trigger partial mode – other errors (bugs in initialization hooks, coercion failures) propagate normally. An `error` key appears with the error message, and sections that require a valid instance degrade gracefully:

```ruby
info = Order::Place.explain(product: "not an id")
info[:error]      # => "Literal::TypeError: ..."
info[:props]      # => {}
info[:guards]     # => { passed: false, results: [] }
info[:callable]   # => false

info[:record]     # => { enabled: true, params: true, result: true, status: :ready }
info[:callbacks]  # => { before: 1, after: 2, around: 0 }
info[:pipeline]   # => [:trace, :result, :guard, :once, ...]
```

Class-level information (record, transaction, rescue, callbacks, pipeline) is always available. Instance-dependent sections (props, guards, once key, lock key) report empty or nil values. Context mappings and source tracking still work – only resolved values require a valid instance. Static advisory lock keys (string literals) are preserved even in partial mode. Context source reports `:missing` for props that have no default and no ambient value.

The `error` key is absent when props are valid.

## Custom middleware

Custom middleware can contribute to explain by defining a `_name_explain` class method:

```ruby
module RateLimitWrapper
  module ClassMethods
    def _rate_limit_explain(instance, info)
      settings = instance.class.settings_for(:rate_limit)
      info[:rate_limit] = {
        key: settings[:key],
        max: settings[:max],
        period: settings[:period]
      }
    end
  end
end
```

The explain system calls `_name_explain(instance, info)` for each pipeline step that defines it.

## Use cases

### Console debugging

```ruby
info = Order::Place.explain(product: product, quantity: 2)
info[:once]
# => { active: true, key: "Order::Place/product_id=7/quantity=2", status: :exists, ... }
# Aha – there's an existing record with this key. That's why it's replaying.
```

### Admin tooling

```ruby
info = Order::Cancel.explain(order: order)

if info[:callable]
  render partial: "confirm_cancel", locals: { info: info }
else
  failed = info[:guards][:results].reject { |g| g[:passed] }
  render partial: "cannot_cancel", locals: { reasons: failed }
end
```

### LLM agent preflight

```ruby
info = Order::Place.explain(product: product, customer: customer, quantity: requested)

unless info[:callable]
  blockers = info[:guards][:results].reject { |g| g[:passed] }.map { |g| g[:name] }
  agent.report_infeasible(blockers)
end
```

## Relationship to callable / callable?

`callable` and `callable?` evaluate guards only and return `Ok`/`Err` or `true`/`false`. They're optimized for the "should I show this button?" use case.

`explain` is the superset – it evaluates everything and returns a comprehensive report. `explain[:callable]` is a stronger check than `callable?` – it also considers `once` blocking statuses (`:invalid`, `:pending`, `:misconfigured`, `:unavailable`). An operation that passes all guards but has a misconfigured once key reports `callable: false`.
