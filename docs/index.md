---
description: "dexkit documentation – Rails operations, events, forms, and queries with typed APIs, structured errors, async jobs, and testing helpers."
layout: home

hero:
  name: dexkit
  text: Patterns for Rails, crafted for DX
  tagline: "Typed operations, domain events, form objects, and query builders – four base classes your Rails app needs to roll with advantage."
  actions:
    - theme: brand
      text: Get Started
      link: /guide/introduction
    - theme: alt
      text: View on GitHub
      link: https://github.com/razorjack/dexkit

features:
  - title: Dex::Operation
    details: Service objects with typed props, structured errors, transactions, callbacks, async execution, advisory locks, and database recording.
    link: /operation/
    linkText: Learn more
  - title: Dex::Event
    details: Immutable domain events with pub/sub, async handlers via ActiveJob, retries with backoff, causality tracing, and optional persistence.
    link: /event/
    linkText: Learn more
  - title: Dex::Query
    details: Declarative filters and sorts for ActiveRecord and Mongoid scopes – type coercion from params, scope injection, and Rails form binding.
    link: /query/
    linkText: Learn more
  - title: Dex::Form
    details: Form objects with typed fields, normalization, validation, nested forms, ambient context, JSON Schema export, and full Rails form builder compatibility.
    link: /form/
    linkText: Learn more
  - title: Testing built in
    details: Minitest helpers for operations and events – execution, assertions, stubs, spies, contract verification, and a global activity log.
    link: /operation/testing
    linkText: See testing docs
  - title: Registry & Export
    details: Auto-tracked class registry, contract export as hashes or JSON Schema, description DSL for operations, events, and forms, and a rake task for bulk export.
    link: /tooling/registry
    linkText: See export docs
  - title: Guards & Explain
    details: Declare preconditions as guards, check "can this run?" from views and controllers, and run side-effect-free preflight checks with explain.
    link: /operation/guards
    linkText: See guards docs
  - title: DX Meets AI
    details: Consistent, typed patterns that coding agents understand on first read. Turn operations into LLM-callable tools via ruby-llm, and ship optimized guides with rake dex:guides.
    link: /guide/ai
    linkText: Learn more
---
