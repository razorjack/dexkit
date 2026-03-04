Dexkit. Module name: `Dex`

Ruby library providing base classes for service/operation, event, and form object patterns in Rails apps.

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
    concern.rb           # Dex::Concern (module inclusion helper)
    ref_type.rb          # Dex::RefType (Literal::Type for model references)
    type_coercion.rb     # Dex::TypeCoercion (shared serialization/coercion for Operation + Event)
    props_setup.rb       # Dex::PropsSetup (shared prop/prop?/_Ref DSL for Operation + Event)
    error.rb             # Dex::Error
    match.rb             # Dex::Ok, Dex::Err aliases + Dex::Match
    operation.rb         # Operation class orchestrator (requires all parts)
    operation/
      settings.rb        # Dex::Settings
      result_wrapper.rb  # Dex::ResultWrapper
      record_wrapper.rb  # Dex::RecordWrapper
      transaction_wrapper.rb # Dex::TransactionWrapper
      lock_wrapper.rb    # Dex::LockWrapper
      async_wrapper.rb   # Dex::AsyncWrapper
      safe_wrapper.rb    # Dex::SafeWrapper
      rescue_wrapper.rb  # Dex::RescueWrapper
      callback_wrapper.rb # Dex::CallbackWrapper
      pipeline.rb        # Operation::Pipeline + Step
      outcome.rb         # Operation::Ok, Err, SafeProxy
      async_proxy.rb     # Operation::AsyncProxy
      record_backend.rb  # Operation::RecordBackend + adapters
      transaction_adapter.rb # Operation::TransactionAdapter + adapters
      jobs.rb            # const_missing + lazy DirectJob/RecordJob
    event.rb             # Event class orchestrator (requires all parts)
    event/
      metadata.rb        # Dex::Event::Metadata (id, timestamp, trace_id, caused_by_id, context)
      trace.rb           # Dex::Event::Trace (stack-based causality tracing)
      suppression.rb     # Dex::Event::Suppression (block-scoped suppression)
      bus.rb             # Dex::Event::Bus (global pub/sub, sync/async dispatch, persistence)
      handler.rb         # Dex::Event::Handler (on, retries DSL, perform contract)
      processor.rb       # Dex::Event::Processor (ActiveJob, lazy-loaded via const_missing)
    test_log.rb          # Dex::TestLog (global activity log for tests)
    test_helpers.rb      # Dex::TestHelpers + Dex::TestWrapper
    test_helpers/
      execution.rb       # call_operation, call_operation!
      assertions.rb      # All assertion methods
      stubbing.rb        # stub_operation, spy_on_operation, Spy class
    event_test_helpers.rb # Dex::Event::TestHelpers + EventTestWrapper
    event_test_helpers/
      assertions.rb      # assert_event_published, refute_event_published, etc.
    form.rb              # Form class orchestrator (requires all parts)
    form/
      nesting.rb         # Dex::Form::Nesting (nested_one, nested_many DSL)
      uniqueness_validator.rb # Dex::Form::UniquenessValidator (validates :x, uniqueness: true)
    query.rb             # Query class orchestrator (requires all parts)
    query/
      backend.rb         # Dex::Query::Backend (AR + Mongoid adapters, strategy implementations)
      filtering.rb       # Dex::Query::Filtering (filter DSL, registry, _apply_filters)
      sorting.rb         # Dex::Query::Sorting (sort DSL, registry, _apply_sort)

test/
  test_helper.rb         # Minitest setup
  support/
    operation_helpers.rb # define_operation(), with_recording()
    database_helpers.rb  # setup_test_database()
    event_helpers.rb     # define_event(), build_event(), define_handler(), build_handler()
    form_helpers.rb      # define_form(), build_form()
    query_helpers.rb     # define_query(), build_query(), setup_query_database()
  operation/
    test_*.rb            # Per-feature test files
  event/
    test_*.rb            # Per-feature event test files
  form/
    test_*.rb            # Per-feature form test files
  query/
    test_*.rb            # Per-feature query test files
  test_helpers/
    test_*.rb            # Per-feature test helper tests
  event_test_helpers/
    test_*.rb            # Per-feature event test helper tests
  types/
    test_*.rb            # Per-type test files
```

## Core Dependencies

**Runtime:** `activemodel`, `literal`, `zeitwerk`

**Development:** `activejob`, `activerecord` (for testing Rails integration)

## Development Conventions

Operation logic is split into per-module files under `lib/dex/operation/`. The orchestrator `lib/dex/operation.rb` requires all parts. Each behavior is a separate module registered as a named pipeline step via `use`. New wrapper modules follow the pattern: `self.included` + `ClassMethods` for DSL + `_name_wrap` instance method that calls `yield` to proceed. New wrappers go in `lib/dex/operation/` as their own file. See existing wrappers for reference.

**Naming internal methods**: The `_modulename_` prefix is required only for methods that end up in `Dex::Operation`'s method table — i.e., wrapper modules mixed into Operation via `include`/`use`. This prevents collisions with user-defined methods in Operation subclasses (e.g., in `RecordWrapper` → `_record_enabled?`, `_record_save!`). Standalone classes that are never mixed into or inherited from Operation (e.g., `AsyncProxy`, `Pipeline`, `Jobs`, `Processor`) use plain method names since there is no collision risk.

Tests are scoped per-area, each area in a separate file. Example: `test/operation/test_params.rb` for testing params.

## Process

When you're done adding a new feature or significantly modifying existing one:
1. Update `README.md` accordingly.
2. Update the corresponding file in `guides/llm/` — these are LLM-optimized docs copied into apps that use dexkit. They must be thorough, compact, accurate, and in sync with implementation. Current files: `guides/llm/OPERATION.md` (includes testing), `guides/llm/EVENT.md` (includes testing), `guides/llm/FORM.md` (includes testing), `guides/llm/QUERY.md` (includes testing).

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

- Performing an operation with nonce token (as used nonce tokens need to be saved somewhere)

## Finishing Up

When work is done, end with a short one-sentence summary appropriate for a commit message.
