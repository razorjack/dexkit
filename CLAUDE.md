Dexkit. Module name: `Dex`

This is a Ruby library for my Rails projects. Its purpose is to provide
base classes for patterns such as services/operations or forms objects.

## Library core values

1. It's Ruby, the API to use this library must be beautiful. It must read and feel good.
2. Short is better than verbose but must remain unambiguous.
3. Batteries should always be included by default but possible to opt out.
4. Tests should read like examples. Avoid bloated test files. Test files should be succinct.

## Core dependencies

1. dry-rb: dry-struct, dry-types, dry-validations, dry-monads.
2. Development dependency: Rails / ActiveRecord. The library is supposed to integrate well with Rails, so some tests will use Rails to test the integration.

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


### Development

So far, everything is kept in one file: lib/dex/operation.rb. Keep it this way.
But still, even though we have one file, we need to be modular and clean. These modules will be eventually extracted to separate files,
once the API of the library matures.

Modularity: when it makes sense, keep existing pattern of modularizing each type of behavior and prepending the module on the base class.

### Process

When you're done adding a new feature or significantly modifying existing one, update README.md accordingly.

**Naming internal methods**: All private/internal instance methods in Operation modules MUST be prefixed with underscore `_` (non-negotiable). Additionally, try hard to prefix them with `_modulename_` to clearly indicate which module they belong to. Example: in `RecordWrapper` module, internal methods should be named `_record_enabled?`, `_record_save!`, `_record_attributes`, etc. This prevents naming collisions and makes it clear these are framework-internal methods.

Tests can be scoped per-area, each area in a separate file. Example: test/operation/test_params.rb for testing params.

### Future plans

- Ability to define params contract (using dry-validation)
- Wrapping operation response hash into params-like object (basically a dry-struct) so that result objects can be accessed in dot notation, not hash notation.
- Recording operation calls to the database.
  - Also ability to save the response in that record. Possibly connected to wrapping operation response
- Performing an operation with nonce token (connected to recording, as used nonce tokens need to be saved somewhere)
- Monad-like result objects. Success or Failure. Option to swallow Operation::Error exceptions and return Failure with error code
