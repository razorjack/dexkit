---
description: Dex::Tool — turn operations and queries into LLM-callable tools via ruby-llm, with typed params, security boundaries, and structured results.
---

# Tool

`Dex::Tool` turns your operations and queries into tools that LLMs can call directly. It builds on [ruby-llm](https://github.com/crmne/ruby-llm) and uses the [registry](/tooling/registry) and [JSON Schema export](/tooling/registry#json-schema) to generate tool definitions automatically.

## Setup

Add `ruby-llm` to your Gemfile:

```ruby
gem "ruby_llm"
```

`Dex::Tool` is lazy-loaded – it only requires `ruby-llm` when you call it. If the gem isn't installed, you get a clear `LoadError`.

## Operation tools

### From a single operation

```ruby
tool = Dex::Tool.from(Order::Place)
# => RubyLLM::Tool instance
```

The tool's name is derived from the class name (`dex_order_place`), and its parameter schema comes from `contract.to_json_schema`. The operation's `description` becomes the tool description, with guards and error codes appended automatically.

### All operations

```ruby
tools = Dex::Tool.all
# => Array of RubyLLM::Tool instances, one per registered operation
```

### By namespace

```ruby
tools = Dex::Tool.from_namespace("Order")
# => Tools for Order::Place, Order::Cancel, Order::Refund, etc.
```

### How it works

When an LLM calls an operation tool, `Dex::Tool`:

1. Receives the parameters from the LLM as a hash
2. Calls the operation via `.safe.call` (so errors don't raise)
3. On success – returns `value.as_json`
4. On error – returns `{ error: code, message: message, details: details }`

The LLM gets structured feedback either way.

### Guards inform the LLM

Guards and error codes are included in the tool description so the LLM knows what can go wrong before it tries:

```ruby
class Order::Cancel < Dex::Operation
  description "Cancel an existing order"

  prop :order, _Ref(Order)
  error :already_shipped

  guard :not_cancelled, "Order must not already be cancelled" do
    !order.cancelled?
  end

  def perform
    error!(:already_shipped) if order.shipped?
    order.update!(cancelled: true)
  end
end
```

The tool description the LLM sees:

```
Cancel an existing order
Preconditions: Order must not already be cancelled.
Errors: not_cancelled, already_shipped.
```

### Explain tool

`Dex::Tool.explain_tool` creates a special tool that lets the LLM check whether an operation can run before executing it:

```ruby
tools = Dex::Tool.from_namespace("Order") + [Dex::Tool.explain_tool]
chat.with_tools(*tools)
```

The explain tool accepts an operation name and params, runs [explain](/operation/explain) on it, and returns the callable status, guard results, once status, and lock info – without executing anything. The LLM can use this to check preconditions, report why something won't work, or decide which operation to try.

### Recording as audit trail

If your operations use [recording](/operation/recording), every LLM-initiated call is persisted to the database with full params and results. This gives you a complete audit trail of what the LLM did, when, and with what inputs – without any extra work.

## Query tools

Query tools let LLMs search and filter your data using the same `Dex::Query` classes you already have. Unlike operation tools, query tools require explicit security boundaries – a scoped relation and a serialization function.

### Creating a query tool

```ruby
tool = Dex::Tool.from(Order::Query,
  scope: -> { Current.user.orders },
  serialize: ->(r) { r.as_json(only: %i[id status total created_at]) })
```

Both `scope:` and `serialize:` are required. The query class must also have a `scope { ... }` block defined.

### Why scope and serialize are required

**scope:** controls data access. The lambda is evaluated at execution time, so it picks up the current user/tenant. The query class's own `scope { ... }` block defines the base relation shape, but the tool's `scope:` replaces it at call time – ensuring the LLM can only see records the current user is allowed to see.

**serialize:** controls data exposure. Raw ActiveRecord objects would leak every column, association, and internal field. The serialize lambda gives you full control over what the LLM sees.

### Full options

| Option | Type | Default | Description |
|---|---|---|---|
| `scope:` | lambda | *required* | Returns the base scope; evaluated per-call |
| `serialize:` | lambda | *required* | Transforms each record for the LLM |
| `limit:` | Integer | `50` | Maximum results per page |
| `only_filters:` | Array | all visible | Restrict to these filters only |
| `except_filters:` | Array | none | Exclude these filters |
| `only_sorts:` | Array | all declared | Restrict to these sort columns only |

`only_filters:` and `except_filters:` are mutually exclusive.

### What the tool produces

The tool name follows the pattern `dex_query_{class_name_lowercased}` – `::` becomes `_`, then the whole name is lowercased. For example, `Order::Query` becomes `dex_query_order_query`.

The parameter schema is built from the query's props, filters, and sorts. It always includes `limit` and `offset` for pagination. Context-mapped props and `_Ref` props are automatically excluded – the LLM shouldn't be providing user IDs or model references.

The tool description includes the query's `description`, available filters (with enum values when applicable), sort columns (with default noted), and the result limit.

### Execution flow

When an LLM calls a query tool:

1. Extracts `limit`, `offset`, and `sort` from params
2. Clamps `limit` to the configured maximum
3. Validates `sort` against allowed columns (invalid sorts are silently dropped)
4. Evaluates the `scope:` lambda to get the base relation
5. Delegates to `from_params` with the remaining filter params
6. Counts total results, then applies offset/limit
7. Serializes each record with the `serialize:` lambda

### Return shape

Success:

```json
{
  "records": [{ "id": 1, "status": "shipped", "total": 4999 }, ...],
  "total": 142,
  "limit": 50,
  "offset": 0
}
```

Errors:

```json
{ "error": "invalid_params", "message": "..." }
```

```json
{ "error": "query_failed", "message": "..." }
```

`invalid_params` covers bad types or invalid filter values. `query_failed` catches anything else.

### Restricting filters and sorts

Not every filter or sort column should be available to the LLM. Restrict what's exposed:

```ruby
class Order::Query < Dex::Query
  scope { Order.all }

  prop? :status, String
  prop? :customer_name, String
  prop? :internal_code, String

  filter :status
  filter :customer_name, :contains
  filter :internal_code

  sort :created_at, :total, default: "-created_at"
end

tool = Dex::Tool.from(Order::Query,
  scope: -> { Current.user.orders },
  serialize: ->(r) { r.as_json(only: %i[id status total]) },
  except_filters: [:internal_code],
  only_sorts: [:created_at])
```

The LLM can filter by `status` and `customer_name`, sort by `created_at`, but never sees `internal_code` or the `total` sort.

### Why all and from_namespace are operation-only

`Dex::Tool.all` and `Dex::Tool.from_namespace` work for operations because operations are self-contained – they don't need per-instance security configuration. Query tools always need `scope:` and `serialize:`, which vary by context (current user, tenant, API endpoint), so each query tool must be created explicitly with `Dex::Tool.from`.

## Security model

Query tools enforce five layers of security:

| Layer | Mechanism | What it prevents |
|---|---|---|
| **Scope injection** | `scope:` lambda evaluated per-call | LLM accessing records outside the user's permission boundary |
| **Serialization** | `serialize:` lambda per-record | Leaking internal columns, associations, or sensitive fields |
| **Result limiting** | `limit:` option (default 50) | Unbounded data extraction |
| **Filter allowlisting** | `only_filters:` / `except_filters:` | Exposing internal or sensitive filter dimensions |
| **Sort allowlisting** | `only_sorts:` | Exposing internal sort columns |

All five are enforced by the tool infrastructure – the LLM cannot bypass them regardless of what parameters it sends.

## Serialization

### Simple as_json

```ruby
Dex::Tool.from(Order::Query,
  scope: -> { Current.user.orders },
  serialize: ->(r) { r.as_json(only: %i[id status total created_at]) })
```

### With a serializer (Alba, Blueprinter, etc.)

```ruby
Dex::Tool.from(Order::Query,
  scope: -> { Current.user.orders.includes(:line_items) },
  serialize: ->(r) { OrderSerializer.new(r).to_h })
```

The serialize lambda receives a single record and returns a hash (or anything JSON-serializable). Use `includes` in your scope to avoid N+1 queries.

## Context integration

If your operations or queries use [ambient context](/operation/context), wrap the LLM interaction in `Dex.with_context`. Context-mapped props are automatically excluded from the tool schema – the LLM never sees or provides them.

```ruby
Dex.with_context(current_customer: current_user) do
  chat = RubyLLM.chat(model: "gpt-5-mini")

  tools = Dex::Tool.from_namespace("Order") + [
    Dex::Tool.from(Order::Query,
      scope: -> { current_user.orders },
      serialize: ->(r) { r.as_json(only: %i[id status total]) }),
    Dex::Tool.explain_tool
  ]

  chat.with_tools(*tools)
  chat.ask("Show me my recent orders, then cancel the one from last week")
end
```

The operation resolves `current_customer` from the ambient context, and the query tool's `scope:` lambda captures `current_user` from the surrounding block. The LLM never handles authentication.

## Agentic Rails endpoint

A minimal controller that exposes both operations and queries as LLM tools:

```ruby
class AgentController < ApplicationController
  def chat
    tools = [
      *Dex::Tool.from_namespace("Order"),
      Dex::Tool.from(Order::Query,
        scope: -> { current_user.orders },
        serialize: ->(r) { r.as_json(only: %i[id status total created_at]) }),
      Dex::Tool.explain_tool
    ]

    Dex.with_context(current_customer: current_user) do
      chat = RubyLLM.chat(model: "gpt-5-mini")
      chat.with_tools(*tools)
      response = chat.ask(params[:message])
      render json: { reply: response.content }
    end
  end
end
```

The LLM can search orders, check preconditions with explain, and execute operations – all within the current user's context and with a full audit trail if recording is enabled.

## End-to-end example

A customer support agent that can look up orders and process cancellations:

```ruby
# The query
class Order::Query < Dex::Query
  description "Search customer orders by status or date"

  scope { Order.all }

  prop? :status, _Union("pending", "shipped", "delivered", "cancelled")
  prop? :customer, _Ref(Customer)

  context customer: :current_customer

  filter :status
  sort :created_at, default: "-created_at"
end

# The operation
class Order::Cancel < Dex::Operation
  description "Cancel an order"

  prop :order, _Ref(Order)
  prop :customer, _Ref(Customer)
  error :already_shipped

  context customer: :current_customer

  guard :not_cancelled, "Order must not already be cancelled" do
    !order.cancelled?
  end

  def perform
    error!(:already_shipped) if order.shipped?
    order.update!(status: :cancelled)
    { id: order.id, status: "cancelled" }
  end
end
```

```ruby
# Wire them up
tools = [
  Dex::Tool.from(Order::Query,
    scope: -> { Current.user.orders },
    serialize: ->(r) { r.as_json(only: %i[id status total created_at]) }),
  Dex::Tool.from(Order::Cancel),
  Dex::Tool.explain_tool
]

Dex.with_context(current_customer: Current.user) do
  chat = RubyLLM.chat(model: "gpt-5-mini")
  chat.with_tools(*tools)
  chat.ask("Find my pending orders and cancel the oldest one")
end
```

The LLM first queries for pending orders (scoped to the current user), picks the oldest one, optionally checks with explain, then calls `Order::Cancel`. Every step produces structured data the LLM can reason about, and every operation call is recorded if recording is enabled.
