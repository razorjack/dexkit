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
    types.rb             # Dex::Types::Extension (adds Record() type)
    operation.rb         # All operation logic and wrapper modules

test/
  test_helper.rb         # Minitest setup, Types module
  support/
    operation_helpers.rb # define_operation(), with_recording()
    database_helpers.rb  # setup_test_database()
  operation/
    test_*.rb            # Per-feature test files
  types/
    test_*.rb            # Per-type test files
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
    puts "Welcome #{name}"
  end
end


# Call
TestMyOperation.new(name: "Test Test!").call
```

### Async operations

```Ruby
TestMyOperation.new(name: "Test Test!").async.call
TestMyOperation.new(name: "Test Test!").async(at: 3.days.from.now).call
TestMyOperation.new(name: "Test Test!").async(in: 3.minutes, queue: "low").call
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
| ResultWrapper | Typed results via `result` block, `error!` method | Active |
| AsyncWrapper | Background execution via `.async.call` | Opt-in |
| SafeWrapper | Safe execution via `.safe` returning `Ok`/`Err` | Active |
| TransactionWrapper | Wraps `perform` in DB transaction | Enabled |
| LockWrapper | Advisory locking via `advisory_lock` | Opt-in |
| RecordWrapper | Logs operation calls to database | Requires config |
| RescueWrapper | Maps exceptions to `Dex::Error` via `rescue_from` | Active |
| CallbackWrapper | Lifecycle hooks via `before`, `after`, `around` | Active |

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

### LLM Documentation (`guides/llm/`)

**CRITICAL:** This library provides LLM-optimized documentation in `guides/llm/` for use by AI coding agents.

**Purpose:** Files in `guides/llm/` are designed to be copied into applications that use dexkit (e.g., `app/operations/CLAUDE.md` or `app/operations/AGENTS.md`). When developers work on operations in their apps, coding agents automatically load these instructions and know the complete API.

**Maintenance rule:** Whenever you add a new feature or significantly modify an existing feature in any of the library's major components (Operation, etc.), you MUST update the corresponding file in `guides/llm/` to reflect the changes. These files must remain:

1. **Thorough** — Document EVERY feature, DSL method, option, and behavior
2. **Compact** — Optimize for information density; avoid unnecessary prose
3. **LLM-optimized** — Use clear headings, code examples, tables, and structured lists that LLMs parse well
4. **Accurate** — Keep in sync with implementation; test examples work

**Current files:**
- `guides/llm/OPERATION.md` — Complete reference for Dex::Operation

As new major features are added (e.g., Forms, Validators), create corresponding files like `guides/llm/FORM.md`.

### Code Quality

**Rubocop is mandatory.** After modifying any Ruby files (`.rb`), always run:

```bash
bundle exec rubocop
```

To auto-fix issues: `bundle exec rubocop -a`

For markdown files with Ruby code snippets:

```bash
bundle exec rubocop -c .rubocop-md.yml
```

### Implemented Features

- ✅ Typed result objects via `result do` block (dry-struct based)
- ✅ Explicit failure signaling via `error!` method
- ✅ Monad-like result objects (`Ok`/`Err`) via `.safe` modifier
- ✅ Pattern matching support for errors and outcomes
- ✅ Operation response recording to database with granular control (`record params: false, response: false`)
- ✅ `Types::Record(Model)` - parameterized type for model instances with ID coercion and serialization
- ✅ Lifecycle callbacks (`before`, `after`, `around`) with symbol, lambda, and block support
- ✅ Exception mapping via `rescue_from` — converts third-party exceptions to `Dex::Error` with inheritance support
- ✅ `.call` as public entry point, `perform` is private (user-implemented); double-prepend guard for multi-level inheritance
- ✅ Parameter delegation — params accessible directly in `perform` (e.g., `name` instead of `params.name`), configurable via `delegate:` option
- ✅ Record-based async strategy — when recording is enabled, async jobs store only a record ID in Redis instead of the full params payload; status tracking (`pending` → `running` → `done`/`failed`) with error field
- ✅ Advisory locking via `advisory_lock` DSL — wraps operation in database advisory lock (outside transaction boundary); supports static keys, dynamic blocks, symbol methods, timeout; uses `with_advisory_lock` gem as optional runtime dependency

### Future plans

- Ability to define params contract (using dry-validation)
- Performing an operation with nonce token (as used nonce tokens need to be saved somewhere)
