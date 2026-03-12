---
description: "Why dexkit's explicit Ruby APIs, consistent conventions, and prescriptive errors make it a natural fit for AI coding agents and LLM tool integration."
---

# DX Meets AI

dexkit's [design principles](/guide/philosophy) – explicit declarations, typed contracts, prescriptive errors – were chosen for developers. But there's a second audience that benefits just as much: coding agents. The same properties that make code pleasant to read and maintain are exactly what make it easy for an AI to work with.

## The research problem

When a coding agent hits a typical Rails codebase, it scans 3–5 existing service objects to learn the team's patterns. It notices inconsistencies – one returns a hash, another raises, another returns a boolean. It makes judgment calls about which to follow. If the team uses a niche gem, the agent may hallucinate its API entirely. Then it repeats the whole process for tests.

With dexkit, that research phase almost disappears. The DSL *is* the convention – every operation has the same shape, so learning one means knowing them all.

## Token efficiency

dexkit ships [LLM-optimized guides](https://github.com/razorjack/dexkit/tree/master/guides/llm) you install as `AGENTS.md` files via `rake dex:guides`. The agent reads ~550 lines instead of scanning thousands across dozens of files – roughly a 5–7x reduction in context tokens and 2–4 fewer agent loop turns. Guides are versioned with the gem, so `bundle update dexkit` keeps them accurate.

## Code as documentation

```ruby
class Order::Place < Dex::Operation
  description "Place a new order for a customer"

  prop :customer, _Ref(Customer), desc: "The customer placing the order"
  prop :product, _Ref(Product)
  prop :quantity, _Integer(1..)
  prop? :note, String

  context customer: :current_customer

  success _Ref(Order)
  error :out_of_stock

  guard :active_customer, "Customer account must be active" do
    !customer.suspended?
  end
end
```

Without reading `perform`, an agent (or a human) knows: what the operation does, what it accepts, which inputs are optional, what types are expected, which prop comes from ambient context, what it returns, which errors it can raise, and under what preconditions it refuses to run. A typical service object requires tracing the entire method body for half of that information.

## Quick feedback

Agents hallucinate, and the best defense is catching mistakes immediately. `error!(:wrong_code)` raises `ArgumentError` if the code isn't declared. `prop :email, 123` raises because that's not a valid type. Each error message tells the agent exactly how to fix it – read, correct, move on. No silent failures that pass review and break at runtime.

## Prescribed architecture

Controller → Form (validates, normalizes) → Operation (transacts, persists) → Model. The agent never has to decide "should the form save directly?" or "who validates?" – the answers are built in.

## Operations as LLM tools

dexkit doesn't just play well with coding agents – it integrates directly with LLMs at runtime. Every operation can become a tool that an LLM calls:

```ruby
tools = Dex::Tool.from_namespace("Order")
chat = RubyLLM.chat(model: "gpt-5-mini")
chat.with_tools(*tools)
chat.ask("Place an order for product 7, quantity 2")
```

The LLM sees typed parameters (from [JSON Schema export](/tooling/registry#json-schema)), guard preconditions in the tool description, and gets structured `Ok`/`Err` feedback. Context-mapped props like `current_customer` resolve from the ambient context – the LLM never sees or provides them. If [recording](/operation/recording) is on, every LLM-initiated call is persisted with full params and results – a complete audit trail with zero extra work.

There's even an [explain tool](/operation/explain) the LLM can use to check whether an operation will succeed before executing it – inspecting guards, idempotency keys, and lock status without side effects.

## Why it compounds

Without structure, ten agent-generated service objects will have ten slightly different patterns. With dexkit, you can't write an inconsistent operation when `prop`, `error`, `success`, and `perform` are the only moving parts. Conventions aren't in a style guide; they're baked into the framework.

Don't document rules – enforce them mechanically. Make error messages prescriptive so agents self-correct. Build on well-understood technology that's everywhere in training data. Keep specs in the repo, not in someone's head. OpenAI's [Harness Engineering](https://openai.com/index/harness-engineering) article lays out these principles for agent-heavy teams. dexkit was designed around them.
