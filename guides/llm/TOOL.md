# Dex::Tool — LLM Reference

Install with `rake dex:guides` or copy manually to `AGENTS.md`.

---

## Overview

`Dex::Tool` bridges Dex primitives to LLM tool calling via ruby-llm. It accepts Operation or Query classes and returns `RubyLLM::Tool` instances ready for `chat.with_tools(...)`.

Requires `gem "ruby_llm"` in your Gemfile. Lazy-loaded — ruby-llm is only required when you call `Dex::Tool`.

---

## Operation Tools

### Creating

```ruby
tool = Dex::Tool.from(Orders::Place)       # single operation
tools = Dex::Tool.all                       # all registered operations
tools = Dex::Tool.from_namespace("Orders")  # operations under Orders::
```

`from` accepts no options for Operation classes. `all` and `from_namespace` return sorted arrays.

### Tool Schema

The tool name is derived from the class name: `Orders::Place` becomes `dex_orders_place`.

The description includes:
- The operation's `description` (or class name if none)
- Guard preconditions (if any)
- Declared error codes (if any)

The params schema is the operation's `contract.to_json_schema`.

### Execution Flow

1. Params are symbolized
2. Operation is instantiated with params
3. Called via `.safe.call` (returns `Ok` or `Err`, never raises)
4. `Ok` — returns `value.as_json` (or raw value if no `as_json`)
5. `Err` — returns `{ error:, message:, details: }`

### Example

```ruby
class Orders::Place < Dex::Operation
  description "Place a new order for a customer"

  prop :customer_id, _Ref(Customer)
  prop :product_id, _Ref(Product)
  prop? :quantity, Integer, default: 1

  error :out_of_stock, :invalid_quantity

  guard :sufficient_stock, "Product must be in stock" do
    Product.find(product_id).stock >= quantity
  end

  def perform
    error!(:invalid_quantity) if quantity <= 0
    Order.create!(customer_id: customer_id, product_id: product_id, quantity: quantity)
  end
end

tool = Dex::Tool.from(Orders::Place)
chat = RubyLLM.chat.with_tools(tool)
chat.ask("Place an order for customer #12, product #42, quantity 3")
```

### Error Shape

When an operation returns `Err`, the tool returns:

```ruby
{ error: :out_of_stock, message: "out_of_stock", details: nil }
```

---

## Explain Tool

A meta-tool that checks whether an operation can execute with given params, without running it:

```ruby
tool = Dex::Tool.explain_tool
chat = RubyLLM.chat.with_tools(tool)
chat.ask("Can I place an order for product #42?")
```

The LLM calls it with `{ operation: "Orders::Place", params: { product_id: 42 } }`. Returns:

```ruby
{ callable: true, guards: [{ name: :sufficient_stock, passed: true }], once: nil, lock: nil }
```

If the operation is not in the registry: `{ error: "unknown_operation", message: "..." }`.

---

## Query Tools

### Creating

```ruby
tool = Dex::Tool.from(Product::Query,
  scope: -> { Current.user.products },
  serialize: ->(record) { record.as_json(only: %i[id name price stock]) })
```

### Required Options

Both `scope:` and `serialize:` are mandatory for Query tools.

**`scope:`** — a lambda returning the base relation. Called at execution time:

```ruby
Dex::Tool.from(Order::Query,
  scope: -> { Current.user.orders },
  serialize: ->(r) { r.as_json })

Dex::Tool.from(Product::Query,
  scope: -> { Product.where(active: true) },
  serialize: ->(r) { r.as_json })
```

**`serialize:`** — a lambda converting each record to a hash:

```ruby
Dex::Tool.from(Product::Query,
  scope: -> { Product.all },
  serialize: ->(r) { r.as_json(only: %i[id name price]) })

Dex::Tool.from(Order::Query,
  scope: -> { Current.user.orders },
  serialize: ->(r) { { id: r.id, total: r.total, status: r.status } })
```

### Optional Restrictions

**`limit:`** — max results per page (default: 50). The LLM can request fewer but never more:

```ruby
Dex::Tool.from(Product::Query, scope: -> { Product.all }, serialize: ->(r) { r.as_json }, limit: 25)
```

**`only_filters:`** — allowlist of filters exposed to the LLM:

```ruby
Dex::Tool.from(Product::Query,
  scope: -> { Product.all },
  serialize: ->(r) { r.as_json },
  only_filters: %i[name category])
```

**`except_filters:`** — denylist of filters hidden from the LLM (mutually exclusive with `only_filters:`):

```ruby
Dex::Tool.from(Product::Query,
  scope: -> { Product.all },
  serialize: ->(r) { r.as_json },
  except_filters: %i[internal_code])
```

**`only_sorts:`** — allowlist of sort columns. Must include the query's default sort if one exists:

```ruby
Dex::Tool.from(Product::Query,
  scope: -> { Product.all },
  serialize: ->(r) { r.as_json },
  only_sorts: %i[name price created_at])
```

### Auto-Exclusions

These props are automatically excluded from the tool schema (the LLM never sees them):

- Props mapped via `context` (filled from ambient context)
- `_Ref` typed props (model references)
- Props for hidden filters (via `only_filters:` / `except_filters:`)

If an auto-excluded prop is required with no default and no context mapping, `from` raises `ArgumentError` at build time.

### Tool Schema

The tool name is `dex_query_{class_name}` (lowercased, `::` replaced with `_`).

The description includes:
- The query's `description` (or class name)
- Available filters with type hints and enum values
- Available sorts with default indicator
- Max results per page

The params schema includes visible filter props plus:

- `sort` — enum of allowed sort values (prefix with `-` for descending; custom sorts have no `-` variant)
- `limit` — integer, max results
- `offset` — integer, skip N results (for pagination)

### Execution Flow

1. Extract `limit`, `offset`, `sort` from params
2. Clamp `limit` to max (default 50); zero or negative resets to max
3. Floor `offset` at 0
4. Validate sort value against allowed sorts; drop invalid (falls back to query default)
5. Custom sorts reject `-` prefix (direction is baked into the block)
6. Strip context-mapped and excluded filter params
7. Inject scope from `scope:` lambda
8. Build query via `from_params` (coercion, blank stripping, validation)
9. Resolve, count total, apply offset/limit
10. Serialize each record via `serialize:` lambda

### Return Shape

```json
{
  "records": [{ "id": 1, "name": "Widget", "price": 9.99 }],
  "total": 142,
  "limit": 50,
  "offset": 0
}
```

`total` is `nil` if the count query fails (e.g., complex GROUP BY).

### Error Handling

Invalid params or type errors:

```ruby
{ error: "invalid_params", message: "..." }
```

Any other error:

```ruby
{ error: "query_failed", message: "..." }
```

---

## Context

`Dex.with_context` provides ambient values to both Operation and Query tools. Props with `context` mappings are auto-filled and hidden from the LLM:

```ruby
class Orders::Place < Dex::Operation
  prop :customer_id, _Ref(Customer)
  context customer_id: :current_customer_id
  # ...
end

class Order::Query < Dex::Query
  scope { Order.all }
  prop? :customer_id, _Ref(Customer)
  context customer_id: :current_customer_id
  filter :customer_id
  # ...
end

Dex.with_context(current_customer_id: current_user.customer_id) do
  chat.ask("Show me my recent orders")
end
```

The LLM never sees `customer_id` in either tool's schema — it is injected from context.

---

## Security Model

Five layers protect against misuse:

1. **Scope lambda** — called at execution time, applies authorization (`Current.user.orders`, `policy_scope(...)`)
2. **Context injection** — security-sensitive props (tenant, user) are filled from ambient context, invisible to the LLM
3. **Filter restrictions** — `only_filters:` / `except_filters:` control what the LLM can search on
4. **Sort restrictions** — `only_sorts:` limits available sort columns
5. **Limit cap** — `limit:` sets a hard ceiling on results per page; the LLM cannot exceed it

---

## Combining Operation + Query Tools

```ruby
order_tools = Dex::Tool.from_namespace("Orders")

search_tool = Dex::Tool.from(Product::Query,
  scope: -> { Current.user.products },
  serialize: ->(r) { r.as_json(only: %i[id name price stock]) },
  limit: 20,
  only_filters: %i[name category],
  only_sorts: %i[name price])

explain = Dex::Tool.explain_tool

chat = RubyLLM.chat
chat.with_tools(*order_tools, search_tool, explain)

Dex.with_context(current_customer_id: current_user.customer_id) do
  chat.ask("Find products under $50, then place an order for the cheapest one")
end
```

---

**End of reference.**
