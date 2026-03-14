---
description: "A Ruby toolkit for structuring Rails business logic — typed operations, domain events, form objects, and query builders with contracts that enforce themselves."
layout: home

hero:
  name: dexkit
  text: Typed patterns for Rails, crafted for DX
  tagline: "Operations, events, forms, and queries – four base classes with contracts that enforce themselves. Equip to roll with advantage."
  actions:
    - theme: brand
      text: Get Started
      link: /guide/introduction
    - theme: alt
      text: View on GitHub
      link: https://github.com/razorjack/dexkit

features:
  - title: Dex::Operation
    details: Encapsulate a business action with typed inputs and structured errors. Transactions, callbacks, async, and tracing are built into the pipeline.
    link: /operation/
    linkText: Learn more
  - title: Dex::Event
    details: Publish typed, immutable domain events and react with handler classes. Async dispatch, retries, causality tracing, and persistence are built in.
    link: /event/
    linkText: Learn more
  - title: Dex::Query
    details: Declare filters and sorts for ActiveRecord and Mongoid scopes. Params coercion, scope composition, and Rails form binding included.
    link: /query/
    linkText: Learn more
  - title: Dex::Form
    details: Define form objects with typed fields, validation, and nested forms. Works with Rails form builders and exports to JSON Schema.
    link: /form/
    linkText: Learn more
  - title: Testing built in
    details: Minitest helpers for operations and events — assertions, stubs, spies, and a global activity log for verifying what ran and why.
    link: /operation/testing
    linkText: See testing docs
  - title: Registry & Export
    details: Every operation, event, form, and query is auto-tracked in a registry. Export contracts as hashes or JSON Schema with a single rake task.
    link: /tooling/registry
    linkText: See export docs
  - title: Guards & Explain
    details: Declare preconditions as named guards and check "can this run?" from views and controllers. Explain runs a full preflight check with no side effects.
    link: /operation/guards
    linkText: See guards docs
  - title: DX Meets AI
    details: Typed, consistent patterns that AI coding agents understand on first read. Turn operations into LLM-callable tools via ruby-llm.
    link: /guide/ai
    linkText: Learn more
---
