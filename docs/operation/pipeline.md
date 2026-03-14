---
description: Dex::Operation middleware — inspect the execution pipeline, understand wrapper ordering, and add custom steps with the use DSL.
---

# Middleware

Every operation runs through a pipeline of middleware steps. Understanding the pipeline is useful for debugging, and the `use` API lets you extend it with custom behavior.

## Default pipeline

The default pipeline, from outermost to innermost:

```
trace > result > guard > once > lock > record > transaction > rescue > callbacks > perform
```

Each step wraps everything inside it. `trace` assigns the execution ID and pushes the operation frame before anything else runs. `record` wraps `transaction`, `rescue`, `callbacks`, and `perform` – so all outcomes (success, error, exception) are captured regardless of transaction rollbacks.

## Inspecting the pipeline

```ruby
Employee::Onboard.pipeline.steps
# => [
#   #<data name=:trace, method=:_trace_wrap>,
#   #<data name=:result, method=:_result_wrap>,
#   #<data name=:guard, method=:_guard_wrap>,
#   #<data name=:once, method=:_once_wrap>,
#   #<data name=:lock, method=:_lock_wrap>,
#   #<data name=:record, method=:_record_wrap>,
#   #<data name=:transaction, method=:_transaction_wrap>,
#   #<data name=:rescue, method=:_rescue_wrap>,
#   #<data name=:callback, method=:_callback_wrap>
# ]
```

## Writing middleware

A middleware module provides a `_name_wrap` instance method that calls `yield` to proceed. This is the same pattern as Rack middleware or Rails around callbacks.

### Instrumentation

A minimal middleware that emits `ActiveSupport::Notifications` events, letting you hook into every operation from the outside – for logging, metrics, or APM:

```ruby
module InstrumentationWrapper
  def _instrumentation_wrap
    ActiveSupport::Notifications.instrument("dex.operation", operation: self.class.name) do
      yield
    end
  end
end

class ApplicationOperation < Dex::Operation
  use InstrumentationWrapper, at: :outer
end
```

Every operation inheriting from `ApplicationOperation` now emits instrumentation events. Subscribe to them anywhere:

```ruby
ActiveSupport::Notifications.subscribe("dex.operation") do |name, start, finish, id, payload|
  Rails.logger.info "#{payload[:operation]} finished in #{(finish - start).round(3)}s"
end
```

### Rate limiting

A more advanced middleware with a class-level DSL for configuration:

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

The convention: dexkit derives the step name from the module name (stripping `Wrapper` suffix, converting to snake_case).

## Positioning middleware

By default, new middleware is added at the inner end of the pipeline (just before `perform`). You can control placement:

```ruby
# At the outermost position (before everything)
use MyWrapper, at: :outer

# At the innermost position (closest to perform) – the default
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

- `as:` – the step name (defaults to derived from module name)
- `wrap:` – the wrap method name (defaults to `_#{step_name}_wrap`)

## Removing middleware

Pipeline steps can be removed by name:

```ruby
class NoRecordOperation < Dex::Operation
  pipeline.remove(:record)
end
```

## How middleware works

Each step is a method that receives a block (the rest of the pipeline). It must call `yield` to continue execution. If it doesn't yield, the inner steps – including `perform` – are never called.

```ruby
def _my_step_wrap
  # before logic
  yield
  # after logic
end
```
