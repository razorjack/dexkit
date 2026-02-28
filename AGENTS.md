Dexkit. Module name: `Dex`

Ruby library providing base classes for service/operation and form object patterns in Rails apps.

## Core Values

1. Beautiful Ruby API — must read and feel good.
2. Short over verbose, but unambiguous.
3. Batteries included by default, opt-out possible.
4. Tests read like examples — succinct, no bloat.

## File Structure

```
lib/
  dexkit.rb              # Entry point, configuration, Zeitwerk loader
  dex/
    version.rb           # Version constant
    parameters.rb        # Dex::Parameters (Dry::Struct subclass)
    types.rb             # Dex::Types::Extension (adds Ref() type)
    operation.rb         # All operation logic and wrapper modules
    test_log.rb          # Dex::TestLog (global activity log for tests)
    test_helpers.rb      # Dex::TestHelpers + Dex::TestWrapper
    test_helpers/
      execution.rb       # call_operation, call_operation!
      assertions.rb      # All assertion methods
      stubbing.rb        # stub_operation, spy_on_operation, Spy class

test/
  test_helper.rb         # Minitest setup, Types module
  support/
    operation_helpers.rb # define_operation(), with_recording()
    database_helpers.rb  # setup_test_database()
  operation/
    test_*.rb            # Per-feature test files
  test_helpers/
    test_*.rb            # Per-feature test helper tests
  types/
    test_*.rb            # Per-type test files
```

## Core Dependencies

**Runtime:** `dry-struct`, `zeitwerk`

**Development:** `activejob`, `activerecord` (for testing Rails integration)

## Development Conventions

All operation logic lives in `lib/dex/operation.rb` — keep it this way until the API matures. Each behavior is a separate module registered as a named pipeline step via `use`. New wrapper modules follow the pattern: `self.included` + `ClassMethods` for DSL + `_name_wrap` instance method that calls `yield` to proceed. See existing wrappers for reference.

**Naming internal methods**: All private/internal instance methods in Operation modules MUST be prefixed with underscore `_` (non-negotiable). Additionally, prefix them with `_modulename_` to indicate which module they belong to. Example: in `RecordWrapper` → `_record_enabled?`, `_record_save!`, `_record_attributes`. This prevents naming collisions and signals framework-internal methods.

Tests are scoped per-area, each area in a separate file. Example: `test/operation/test_params.rb` for testing params.

## Process

When you're done adding a new feature or significantly modifying existing one:
1. Update `README.md` accordingly.
2. Update the corresponding file in `guides/llm/` — these are LLM-optimized docs copied into apps that use dexkit. They must be thorough, compact, accurate, and in sync with implementation. Current files: `guides/llm/OPERATION.md`, `guides/llm/TESTING.md`. New major features get new files (e.g., `guides/llm/FORM.md`).

## Code Quality

**Rubocop is mandatory.** After modifying any Ruby files:

```bash
bundle exec rubocop
```

Auto-fix: `bundle exec rubocop -a`

For markdown files with Ruby snippets:

```bash
bundle exec rubocop -c .rubocop-md.yml
```

**DSL validation:** All DSL methods (`error`, `rescue_from`, `async`, `record`, `advisory_lock`, `before`/`after`/`around`, `transaction`, etc.) validate their arguments at declaration time, raising `ArgumentError` for invalid inputs. The low-level `set` method stays unvalidated — it's the extensible foundation. When adding new DSL methods, always validate arguments early.

## Future Plans

- Ability to define params contract (using dry-validation)
- Performing an operation with nonce token (as used nonce tokens need to be saved somewhere)

## Finishing Up

When work is done, end with a short one-sentence summary appropriate for a commit message.
