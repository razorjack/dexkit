---
description: "Why dexkit emphasizes explicit Ruby APIs, consistent conventions, and LLM-friendly guides for faster human and AI development."
---

# DX Meets AI

dexkit was built for developers who write poetic Ruby. But there's a second audience that benefits just as much: coding agents. The same properties that make code pleasant to read – explicit declarations, consistent structure, typed interfaces – are exactly what make it easy for an AI to work with.

## The research problem

When a coding agent hits a typical Rails codebase, it scans 3–5 existing service objects to learn the team's patterns. It notices inconsistencies – one returns a hash, another raises, another returns a boolean. It makes judgment calls about which to follow. If the team uses a niche gem, the agent may hallucinate its API entirely. Then it repeats the whole process for tests.

With dexkit, that research phase almost disappears. The DSL *is* the convention – every operation has the same shape, so learning one means knowing them all.

## Token efficiency

dexkit ships [LLM-optimized guides](https://github.com/razorjack/dexkit/tree/master/guides/llm) you drop into your project as `CLAUDE.md`. The agent reads ~550 lines instead of scanning thousands across dozens of files – roughly a 5–7x reduction in context tokens and 2–4 fewer agent loop turns. Guides are versioned with the gem, so `bundle update dexkit` keeps them accurate.

## Code as documentation

```ruby
class Order::Place < Dex::Operation
  prop :customer, _Ref(Customer)
  prop :line_items, _Array(Hash)
  prop? :note, String

  success _Ref(Order)
  error :out_of_stock, :invalid_items
end
```

Five lines. Inputs, types, optionality, return type, failure modes – all without reading `perform`. A typical service object requires tracing the entire method body. When an agent writes a controller calling `Order::Place`, the contract tells it what to pass and what to handle. No need to open the implementation.

## Quick feedback

Agents hallucinate, and the best defense is catching mistakes immediately. `error!(:wrong_code)` raises `ArgumentError` if the code isn't declared. `prop :email, 123` raises because that's not a valid type. Each error message tells the agent exactly how to fix it – read, correct, move on. No silent failures that pass review and break at runtime.

## Prescribed architecture

Controller → Form (validates, normalizes) → Operation (transacts, persists) → Model. The agent never has to decide "should the form save directly?" or "who validates?" – the answers are built in.

## Why it compounds

Without structure, ten agent-generated service objects will have ten slightly different patterns. With dexkit, you can't write an inconsistent operation when `prop`, `error`, `success`, and `perform` are the only moving parts. Conventions aren't in a style guide; they're baked into the framework.

Don't document rules – enforce them mechanically. Make error messages prescriptive so agents self-correct. Build on well-understood technology that's everywhere in training data. Keep specs in the repo, not in someone's head. OpenAI's [Harness Engineering](https://openai.com/index/harness-engineering) article lays out these principles for agent-heavy teams. dexkit was designed around them.
