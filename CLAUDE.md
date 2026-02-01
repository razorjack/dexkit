Dexkit. Module name: `Dex`

This is a Ruby library for my Rails projects. Its purpose is to provide
base classes for patterns such as services/operations or forms objects.

## Library core values

1. It's Ruby, the API to use this library must be beautiful. It must read and feel good.
2. Short is better than verbose but must remain unambiguous.
3. Batteries should always be included by default but possible to opt out.
4. Tests should read like examples. Avoid bloated test files. Test files should be succinct.

## File Structure

```
lib/
  dexkit.rb              # Entry point, configuration, Zeitwerk loader
  dex/
    version.rb           # Version constant
    parameters.rb        # Dex::Parameters (Dry::Struct subclass)
    operation.rb         # All operation logic and wrapper modules

test/
  test_helper.rb         # Minitest setup, Types module
  support/
    operation_helpers.rb # define_operation(), with_recording()
    database_helpers.rb  # setup_test_database()
  operation/
    test_*.rb            # Per-feature test files
```

## Core dependencies

**Runtime:** `dry-struct`, `zeitwerk`

**Development:** `activejob`, `activerecord` (for testing Rails integration)

## Operations

The basic API for operation is this:

```Ruby
# Define
class TestMyOperation < Dex::Operation
  params do
    attribute :name, Types::String
  end

  def perform
    puts "Welcome #{params.name}"
  end
end


# Call
TestMyOperation.new(name: "Test Test!").perform
```

### Async operations

```Ruby
TestMyOperation.new(name: "Test Test!").async.perform
TestMyOperation.new(name: "Test Test!").async(at: 3.days.from.now).perform
TestMyOperation.new(name: "Test Test!").async(in: 3.minutes, queue: "low").perform
```

### Settings

Some classes may need class-level configuration. It looks like this:

```Ruby
class TestMyOperation < Dex::Operation
  async queue: "low" # "shortcut" for most-used settings for good DX
  # ...which is equivalent to:
  set :async, queue: "low" # under the hood, all options use `set` API
end
```

### Wrapper Modules

| Module | Purpose | Default |
|--------|---------|---------|
| Settings | Class-level configuration via `set`/`settings_for` | Active |
| ParamsWrapper | Typed parameters via `params` block | Active |
| AsyncWrapper | Background execution via `.async.perform` | Opt-in |
| TransactionWrapper | Wraps `perform` in DB transaction | Enabled |
| RecordWrapper | Logs operation calls to database | Requires config |

### Development

All operation logic is in `lib/dex/operation.rb`. Keep it this way until the API matures. Each behavior is modularized via prepended modules.

Modularity: when it makes sense, keep existing pattern of modularizing each type of behavior and prepending the module on the base class.

#### Module Pattern

The standard pattern for adding new wrapper functionality:

```ruby
module SomeWrapper
  def self.prepended(base)
    class << base
      prepend ClassMethods
    end
  end

  module ClassMethods
    def some_dsl(**opts)
      set(:key, **opts)
    end
  end
end
```

#### Adapter Pattern

Use `.for()` factory methods for adapters:
- `RecordBackend.for(record_class)` - Returns appropriate backend for the model
- `TransactionAdapter.for(adapter_name)` - Returns DB-specific transaction logic

### Process

When you're done adding a new feature or significantly modifying existing one, update README.md accordingly.

**Naming internal methods**: All private/internal instance methods in Operation modules MUST be prefixed with underscore `_` (non-negotiable). Additionally, try hard to prefix them with `_modulename_` to clearly indicate which module they belong to. Example: in `RecordWrapper` module, internal methods should be named `_record_enabled?`, `_record_save!`, `_record_attributes`, etc. This prevents naming collisions and makes it clear these are framework-internal methods.

Tests can be scoped per-area, each area in a separate file. Example: test/operation/test_params.rb for testing params.

### Future plans

- Ability to define params contract (using dry-validation)
- Wrapping operation response hash into params-like object (basically a dry-struct) so that result objects can be accessed in dot notation, not hash notation
- Ability to save the operation response in the database record (connected to wrapping operation response)
- Performing an operation with nonce token (as used nonce tokens need to be saved somewhere)
- Monad-like result objects. Success or Failure. Option to swallow Operation::Error exceptions and return Failure with error code
