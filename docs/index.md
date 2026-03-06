---
description: "dexkit documentation – Rails operations, events, forms, and queries with typed APIs, structured errors, async jobs, and testing helpers."
layout: home

hero:
  name: dexkit
  text: Glorious DX for Rails
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
  - title: Dex::Form
    details: Form objects with ActiveModel attributes, normalization, validation, nested forms, and full Rails form builder compatibility.
    link: /form/
    linkText: Learn more
  - title: Dex::Query
    details: Declarative filters and sorts for ActiveRecord and Mongoid – type coercion from params, scope injection, and Rails form binding.
    link: /query/
    linkText: Learn more
  - title: Testing built in
    details: Minitest helpers for operations and events – execution, assertions, stubs, spies, contract verification, and a global activity log.
    link: /operation/testing
    linkText: See testing docs
  - title: AI agent ready
    details: Ships LLM-optimized guides you drop into your project. Consistent structure means coding agents learn one pattern and know them all.
    link: /guide/philosophy
    linkText: DX meets AI
---
