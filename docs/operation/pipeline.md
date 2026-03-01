# Pipeline & Steps

Every operation runs through a pipeline of wrapper steps. Understanding the pipeline is useful for debugging, and the `use` API lets you extend it with custom behavior.

## Default pipeline

The default pipeline, from outermost to innermost:

```
result > lock > transaction > record > rescue > callbacks > perform
```

Each step wraps everything inside it. For example, `transaction` wraps `record`, `rescue`, `callbacks`, and `perform` — so all of those run inside a database transaction.

## Inspecting the pipeline

```ruby
CreateUser.pipeline.steps
# => [
#   #<data name=:result, method=:_result_wrap>,
#   #<data name=:lock, method=:_lock_wrap>,
#   #<data name=:transaction, method=:_transaction_wrap>,
#   #<data name=:record, method=:_record_wrap>,
#   #<data name=:rescue, method=:_rescue_wrap>,
#   #<data name=:callback, method=:_callback_wrap>
# ]
```

## Adding custom steps

Use `use` to register a module as a pipeline step:

```ruby
module RateLimitWrapper
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def rate_limit(key, max:, period:)
      set(:rate_limit, key: key, max: max, period: period)
    end
  end

  def _rate_limit_wrap
    key = self.class.settings_for(:rate_limit)[:key]
    if RateLimiter.exceeded?(key)
      error!(:rate_limited)
    else
      yield
    end
  end
end

class ApiOperation < Dex::Operation
  use RateLimitWrapper

  rate_limit "api", max: 100, period: 1.minute

  def perform
    # ...
  end
end
```

The convention: your module provides a `_name_wrap` instance method that calls `yield` to proceed to the next step. Dexkit derives the step name from the module name (stripping `Wrapper` suffix, converting to snake_case).

## Positioning steps

By default, new steps are added at the inner end of the pipeline (just before `perform`). You can control placement:

```ruby
# At the outermost position (before everything)
use MyWrapper, at: :outer

# At the innermost position (closest to perform) — the default
use MyWrapper, at: :inner

# Before a specific step
use MyWrapper, before: :transaction

# After a specific step
use MyWrapper, after: :rescue
```

## Explicit naming

If your module name doesn't follow the `XxxWrapper` convention, or you want a different step name:

```ruby
use MyModule, as: :rate_limit, wrap: :_my_custom_wrap_method
```

- `as:` — the step name (defaults to derived from module name)
- `wrap:` — the wrap method name (defaults to `_#{step_name}_wrap`)

## Removing steps

Pipeline steps can be removed by name:

```ruby
class NoRecordOperation < Dex::Operation
  pipeline.remove(:record)
end
```

## How steps work

Each step is a method that receives a block (the rest of the pipeline). It must call `yield` to continue execution. If it doesn't yield, the inner steps — including `perform` — are never called.

```ruby
def _my_step_wrap
  # before logic
  yield
  # after logic
end
```

This is the same pattern as Rack middleware, Rails around callbacks, or any other onion-style architecture.
