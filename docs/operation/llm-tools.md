---
description: Turn Dex::Operation classes into LLM-callable tools with Dex::Tool and the ruby-llm gem – typed params, guards as preconditions, and automatic audit trails.
---

# LLM Tools

`Dex::Tool` turns your operations into tools that LLMs can call directly. It builds on [ruby-llm](https://github.com/crmne/ruby-llm) and uses the [registry](/operation/registry) and [JSON Schema export](/operation/registry#json-schema) to generate tool definitions automatically.

## Setup

Add `ruby-llm` to your Gemfile:

```ruby
gem "ruby_llm"
```

`Dex::Tool` is lazy-loaded – it only requires `ruby-llm` when you call it. If the gem isn't installed, you get a clear `LoadError`.

## Creating tools

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

## How it works

When an LLM calls a tool, `Dex::Tool` does the following:

1. Receives the parameters from the LLM as a hash
2. Calls the operation via `.safe.call` (so errors don't raise)
3. On success – returns `value.as_json`
4. On error – returns `{ error: code, message: message, details: details }`

The LLM gets structured feedback either way.

## Guards inform the LLM

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

## Context flows naturally

If your operations use [ambient context](/operation/context), wrap the LLM interaction in `Dex.with_context`:

```ruby
Dex.with_context(current_customer: current_user) do
  chat = RubyLLM.chat(model: "gpt-5-mini")
  chat.with_tools(*Dex::Tool.from_namespace("Order"))
  chat.ask("Cancel my order #42")
end
```

The operation resolves `current_customer` from the ambient context – the LLM never sees or provides it.

## Explain tool

`Dex::Tool.explain_tool` creates a special tool that lets the LLM check whether an operation can run before executing it:

```ruby
tools = Dex::Tool.from_namespace("Order") + [Dex::Tool.explain_tool]
chat.with_tools(*tools)
```

The explain tool accepts an operation name and params, runs [explain](/operation/explain) on it, and returns the callable status, guard results, once status, and lock info – without executing anything. The LLM can use this to check preconditions, report why something won't work, or decide which operation to try.

## Recording as audit trail

If your operations use [recording](/operation/recording), every LLM-initiated call is persisted to the database with full params and results. This gives you a complete audit trail of what the LLM did, when, and with what inputs – without any extra work.

## Agentic Rails endpoint

A minimal controller that exposes operations as LLM tools:

```ruby
class AgentController < ApplicationController
  def chat
    tools = Dex::Tool.from_namespace("Order") + [Dex::Tool.explain_tool]

    Dex.with_context(current_customer: current_user) do
      chat = RubyLLM.chat(model: "gpt-5-mini")
      chat.with_tools(*tools)
      response = chat.ask(params[:message])
      render json: { reply: response.content }
    end
  end
end
```

The LLM can call any Order operation, check preconditions with explain, and get structured results – all within the current user's context and with a full audit trail if recording is enabled.
