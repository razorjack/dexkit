---
description: "Install dexkit in a Rails app, configure transaction and recording adapters, and set up the optional operation record model."
---

# Installation

Add dexkit to your Gemfile:

```ruby
gem "dexkit"
```

Then run `bundle install`. That's all you need to start using `Dex::Operation`.

## Configuration

dexkit works out of the box with zero configuration. Transactions use ActiveRecord by default, and recording is off until you set it up. If you need to change defaults, create an initializer:

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  # Transaction adapter – :active_record (default) or :mongoid
  config.transaction_adapter = :active_record

  # Recording – set a model class to enable operation recording
  # config.record_class = OperationRecord
end
```

### Transaction adapter

Operations are wrapped in database transactions by default. dexkit supports two adapters:

| Adapter | Value | Uses |
|---|---|---|
| ActiveRecord | `:active_record` | `ActiveRecord::Base.transaction` |
| Mongoid | `:mongoid` | `Mongoid.transaction` |

Set the adapter globally in the initializer, or override per-operation:

```ruby
class MongoidOperation < Dex::Operation
  transaction :mongoid
end
```

### Recording

To record operation executions to a database table, you need a model and a migration. The model can be any ActiveRecord or Mongoid model.

```ruby
# migration
create_table :operation_records do |t|
  t.string :name, null: false
  t.jsonb :params, default: {}
  t.jsonb :response
  t.string :status
  t.string :error
  t.datetime :performed_at
  t.timestamps
end
```

```ruby
# app/models/operation_record.rb
class OperationRecord < ApplicationRecord
end
```

Then point dexkit at it:

```ruby
# config/initializers/dex.rb
Dex.configure do |config|
  config.record_class = OperationRecord
end
```

All columns except `name` are optional – dexkit only writes to columns that exist on the model. See [Recording](/operation/recording) for details on controlling what gets recorded.

### Test setup

```ruby
# test/test_helper.rb
require "dex/test_helpers"

class Minitest::Test
  include Dex::TestHelpers
end
```

See [Testing](/operation/testing) for the full API.
