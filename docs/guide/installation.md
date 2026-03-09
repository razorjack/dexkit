---
description: "Install dexkit in a Rails app – gem setup, configuration, recording, events, async, advisory locking, LLM tools, and test helpers."
---

# Installation

Add dexkit to your Gemfile:

```ruby
gem "dexkit"
```

Then run `bundle install`. That's all you need to start using `Dex::Operation`, `Dex::Event`, `Dex::Form`, and `Dex::Query`.

## Configuration

dexkit works out of the box with zero configuration. ActiveRecord transactions are auto-detected, recording is off until you set it up, and events dispatch without any wiring. Mongoid transactions are available, but they are explicit opt-in. Create an initializer only when you need to change defaults or enable optional features:

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  # Transaction adapter – ActiveRecord auto-detects; set :mongoid explicitly
  # config.transaction_adapter = :mongoid

  # Recording – set a model class to enable operation recording
  # config.record_class = OperationRecord

  # Event persistence – set a model class to persist events to DB
  # config.event_store = EventRecord

  # Event context – capture ambient state when events are published
  # config.event_context = -> { { user_id: Current.user&.id } }

  # Restore context – reconstruct ambient state in async handlers
  # config.restore_event_context = ->(ctx) { Current.user = User.find(ctx["user_id"]) }
end
```

The rest of this page walks through each feature that needs setup, roughly in the order you're likely to need them.

## Transactions

Operations run inside database transactions by default when Dex has an active transaction adapter. ActiveRecord is auto-detected. Mongoid is explicit opt-in because MongoDB transactions require supported topology.

| Adapter | Value | Uses |
|---|---|---|
| ActiveRecord | `:active_record` | `ActiveRecord::Base.transaction` |
| Mongoid | `:mongoid` | `Mongoid.transaction` |

Mongoid transactions are configured explicitly in the initializer or overridden per-operation:

```ruby
Dex.configure do |config|
  config.transaction_adapter = :mongoid
end

class Order::Import < Dex::Operation
  transaction :mongoid
end
```

::: tip
ActiveRecord-backed `after_commit` blocks inside operations require **Rails 7.2+** (specifically `ActiveRecord.after_all_transactions_commit`). Mongoid uses Dex's own callback queue and does not have that Rails version requirement.
:::

::: warning Mongoid requires transaction-capable deployment
Use `:mongoid` only when MongoDB transactions are supported (replica set or sharded cluster). In standalone MongoDB deployments, Dex raises a prescriptive runtime error instead of silently pretending the transaction succeeded.
:::

See [Transactions](/operation/transactions) for details.

## Recording

Record operation executions to a database table for auditing, debugging, or analytics. You need a migration, a model, and one line of config.

### Migration

The migration below includes columns for all recording features. Comment out anything you don't need – dexkit only writes to columns that exist on the model.

```ruby
create_table :operation_records do |t|
  # --- Recording (core) ---
  t.string :name, null: false        # operation class name
  t.jsonb :params                     # serialized props
  t.jsonb :result                     # serialized return value
  t.string :status, null: false       # pending/running/completed/error/failed
  t.string :error_code                # Dex::Error code or exception class
  t.string :error_message             # human-readable message
  t.jsonb :error_details              # structured details hash
  t.datetime :performed_at            # execution completion timestamp

  # --- Idempotency (once) ---
  # Uncomment if you use the `once` DSL for idempotent operations.
  # The unique index prevents race conditions on duplicate calls.
  # once_key_expires_at is only needed if you use `once expires_in:`.
  # t.string :once_key
  # t.datetime :once_key_expires_at

  t.timestamps
end

add_index :operation_records, :name
add_index :operation_records, :status
add_index :operation_records, [:name, :status]
# add_index :operation_records, :once_key, unique: true
```

### Model

```ruby
# app/models/operation_record.rb
class OperationRecord < ApplicationRecord
end
```

Mongoid recording models work too. Define matching fields and the same unique `once_key` index if you use `once`:

```ruby
class OperationRecord
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :params, type: Hash
  field :result, type: Object
  field :status, type: String
  field :error_code, type: String
  field :error_message, type: String
  field :error_details, type: Hash
  field :once_key, type: String
  field :once_key_expires_at, type: Time
  field :performed_at, type: Time

  index({ once_key: 1 }, unique: true, sparse: true)
end
```

### Config

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  config.record_class = OperationRecord
end
```

See [Recording](/operation/recording) for controlling what gets recorded and [Idempotency](/operation/once) for the `once` DSL.

## Advisory locking

The `advisory_lock` DSL wraps operations in database-level mutual exclusion. It is **ActiveRecord-only** and requires the [`with_advisory_lock`](https://github.com/ClosureTree/with_advisory_lock) gem – add it to your Gemfile:

```ruby
gem "with_advisory_lock"
```

No other setup needed. See [Advisory Locking](/operation/advisory-lock) for usage.

## Async operations

Running operations in the background with `.async.call` requires **ActiveJob** (ships with Rails). Your app needs a queue adapter configured – Sidekiq, GoodJob, Solid Queue, or any ActiveJob backend.

No dexkit-specific configuration is needed beyond having ActiveJob working.

See [Async](/operation/async) for usage and recording integration.

## Event handler loading

Handlers subscribe to events via the `on` DSL. There's no separate configuration file that maps events to handlers – the handler class *is* the glue. But **handlers** must be eager-loaded so their `on` declarations run and register subscriptions with the event bus. Events themselves don't need eager loading – they get loaded automatically when handlers reference them.

In Rails with Zeitwerk, add an initializer:

```ruby
# config/initializers/events.rb
Rails.application.config.to_prepare do
  Dex::Event::Bus.clear!
  Dir.glob(Rails.root.join("app/event_handlers/**/*.rb")).each { |e| require(e) }
end
```

`to_prepare` runs on boot and on every code reload in development. `Bus.clear!` prevents duplicate subscriptions across reloads.

Place your handler files in `app/event_handlers/` (or wherever you prefer – just update the glob).

See [Handling Events](/event/handling) for the full handler API.

## Event persistence

By default, events are fire-and-forget – published, dispatched to handlers, and gone. To persist events to a database table, set `event_store` in the initializer:

```ruby
Dex.configure do |config|
  config.event_store = EventRecord
end
```

The store model must respond to `create!(event_type:, payload:, metadata:)`. A simple ActiveRecord model works:

```ruby
# migration
create_table :event_records do |t|
  t.string :event_type, null: false
  t.jsonb :payload, null: false
  t.jsonb :metadata, null: false
  t.timestamps
end

add_index :event_records, :event_type
```

```ruby
# app/models/event_record.rb
class EventRecord < ApplicationRecord
end
```

Mongoid event stores work too:

```ruby
class EventRecord
  include Mongoid::Document
  include Mongoid::Timestamps

  field :event_type, type: String
  field :payload, type: Hash
  field :metadata, type: Hash
end
```

See [Publishing](/event/publishing) for the publish flow and context capture.

## Event async context

Event handlers run via ActiveJob by default. If your handlers need ambient state (like `Current.user`), configure context capture and restoration:

```ruby
Dex.configure do |config|
  config.event_context = -> { { user_id: Current.user&.id } }
  config.restore_event_context = ->(ctx) { Current.user = User.find(ctx["user_id"]) }
end
```

- `event_context` – a callable that returns a hash, evaluated at publish time, stored alongside the event
- `restore_event_context` – a callable that receives the stored hash and reconstructs the ambient state before the handler runs

Without these, async handlers won't have access to request-scoped state like the current user.

## LLM tools

`Dex::Tool` turns operations into tools that LLMs can call directly. It requires the [`ruby-llm`](https://github.com/crmne/ruby-llm) gem:

```ruby
gem "ruby_llm"
```

`Dex::Tool` is lazy-loaded – it only requires ruby-llm when you call it. If the gem isn't installed, you get a clear `LoadError`.

See [LLM Tools](/operation/llm-tools) for usage.

## Test setup

Each pattern has its own test helpers module – include only what you use.

### Operation test helpers

```ruby
# test/test_helper.rb
require "dex/operation/test_helpers"

class Minitest::Test
  include Dex::Operation::TestHelpers
end
```

This gives you `call_operation`, `assert_ok`, `assert_err`, `stub_operation`, `spy_on_operation`, and more. See [Testing](/operation/testing) for the full API.

### Event test helpers

```ruby
# test/test_helper.rb
require "dex/event/test_helpers"

class Minitest::Test
  include Dex::Event::TestHelpers
end
```

This gives you `capture_events`, `assert_event_published`, `refute_event_published`, and trace assertions. Events dispatch synchronously in tests – no ActiveJob needed. See [Testing Events](/event/testing) for the full API.

### Everything at once

If you use multiple patterns, `Dex::TestHelpers` is a convenience that includes all pattern helpers:

```ruby
# test/test_helper.rb
require "dex/test_helpers"

class Minitest::Test
  include Dex::TestHelpers
end
```

## AI coding agents

Install LLM-optimized guides as `AGENTS.md` files in your app directories:

```bash
rake dex:guides
```

This copies reference docs into `app/operations/`, `app/events/`, `app/event_handlers/`, `app/forms/`, and `app/queries/` (only directories that exist). Re-run after upgrading dexkit. See [LLM Guides](/tooling/llm-guides) for details.

## Setup checklist

A quick reference for what each feature needs:

| Feature | What to set up | Required? |
|---|---|---|
| Operations, Forms, Queries | `gem "dexkit"` | Yes |
| Transactions | Nothing (auto-detects ActiveRecord) | Zero-config for ActiveRecord |
| Recording | Migration + model + `config.record_class` | Only if you want recording |
| Idempotency (`once`) | Recording + two extra columns | Only if you use `once` |
| Advisory locking | `gem "with_advisory_lock"` | Only if you use `advisory_lock` |
| Async operations | ActiveJob + queue backend | Only if you use `.async.call` |
| Event handlers | Initializer to load handler files | Yes, if using events |
| Event persistence | Migration + model + `config.event_store` | Only if you want event history |
| Event async context | `config.event_context` + `config.restore_event_context` | Only if async handlers need request state |
| LLM tools | `gem "ruby_llm"` | Only if you use `Dex::Tool` |
| Test helpers | `include Dex::Operation::TestHelpers`, `Dex::Event::TestHelpers`, or both via `Dex::TestHelpers` | Recommended |
| AI coding agents | `rake dex:guides` | Optional |
