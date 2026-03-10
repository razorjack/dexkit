dexkit. Module name: `Dex`

Ruby library providing base classes for service/operation, event, and form object patterns in Rails apps.

## Pre-1.0 Policy

dexkit is pre-1.0. Backwards compatibility is not a concern. There is no migration path obligation between versions. Redundant features, mediocre APIs, and even good features should be removed without hesitation if replaced by a great feature that does the same thing better. Be bold in design decisions — backwards compatibility considerations must not slow down development while we're pre-1.0.

## Core Values

1. Beautiful Ruby API — must read and feel good.
2. Short over verbose, but unambiguous.
3. Batteries included by default, opt-out possible.
4. Tests read like examples — succinct, no bloat.
5. Fail fast, fail loud — invalid inputs, undeclared codes, type mismatches raise immediately with prescriptive error messages. No silent failures.
6. Declare intent, enforce mechanically — contracts are declared at the class level and enforced at runtime. Rules live in code, not in documentation.
7. Own the mechanics, not the domain — execution structure is opinionated, what goes inside isn't.

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
    context_setup.rb     # Dex::ContextSetup (shared context DSL for Operation + Event)
    error.rb             # Dex::Error
    settings.rb          # Dex::Settings (set, settings_for, validate_options!)
    pipeline.rb          # Dex::Pipeline (shared execution pipeline)
    executable.rb        # Dex::Executable (shared skeleton: Settings, Pipeline, use DSL)
    registry.rb          # Dex::Registry (shared subclass registry for Operation, Event, Handler)
    type_serializer.rb   # Dex::TypeSerializer (type → string and type → JSON Schema)
    match.rb             # Dex::Ok, Dex::Err aliases + Dex::Match
    tool.rb              # Dex::Tool (ruby-llm integration, lazy-loaded)
    railtie.rb           # Dex::Railtie (rake tasks, auto-loaded in Rails)
    operation.rb         # Operation class orchestrator (requires all parts)
    operation/
      result_wrapper.rb  # Dex::ResultWrapper
      once_wrapper.rb    # Dex::OnceWrapper
      record_wrapper.rb  # Dex::RecordWrapper
      transaction_wrapper.rb # Dex::TransactionWrapper
      lock_wrapper.rb    # Dex::LockWrapper
      async_wrapper.rb   # Dex::AsyncWrapper
      safe_wrapper.rb    # Dex::SafeWrapper
      rescue_wrapper.rb  # Dex::RescueWrapper
      callback_wrapper.rb # Dex::CallbackWrapper
      guard_wrapper.rb   # Dex::GuardWrapper
      explain.rb         # Dex::Operation::Explain (preflight introspection)
      export.rb          # Dex::Operation::Export (contract.to_h, to_json_schema)
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
      handler.rb         # Dex::Event::Handler (on, retries, callbacks, transaction, pipeline)
      processor.rb       # Dex::Event::Processor (ActiveJob, lazy-loaded via const_missing)
      export.rb          # Dex::Event::Export (to_h, to_json_schema)
    test_log.rb          # Dex::TestLog (global activity log for tests)
    test_helpers.rb      # Dex::TestHelpers (convenience, includes Operation + Event helpers)
    event_test_helpers.rb # backward-compat shim → dex/event/test_helpers
    operation/
      test_helpers.rb    # Dex::Operation::TestHelpers + Dex::Operation::TestWrapper
      test_helpers/
        execution.rb     # call_operation, call_operation!
        assertions.rb    # All assertion methods
        stubbing.rb      # stub_operation, spy_on_operation, Spy class
    event/
      test_helpers.rb    # Dex::Event::TestHelpers + EventTestWrapper
      test_helpers/
        assertions.rb    # assert_event_published, refute_event_published, etc.
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

## Ruby Version

**Minimum: Ruby 3.2.** No support for 3.1 or earlier. This lets us use `Fiber.[]` storage and other 3.2+ features without fallbacks.

## Core Dependencies

**Runtime:** `activemodel`, `literal`, `zeitwerk`

**Development:** `activejob`, `activerecord`, `mongoid` (for testing Rails/Mongoid integration)

## Development Conventions

`Dex::Executable` (`lib/dex/executable.rb`) is the shared execution skeleton providing Settings, Pipeline, `use` DSL, `inherited` hook, and `call`. Both `Dex::Operation` and `Dex::Event::Handler` include it. `Dex::Pipeline` (`lib/dex/pipeline.rb`) is the shared pipeline class.

Operation logic is split into per-module files under `lib/dex/operation/`. The orchestrator `lib/dex/operation.rb` requires all parts. Each behavior is a separate module registered as a named pipeline step via `use`. New wrapper modules follow the pattern: `self.included` + `ClassMethods` for DSL + `_name_wrap` instance method that calls `yield` to proceed. New wrappers go in `lib/dex/operation/` as their own file. See existing wrappers for reference. Wrappers shared between Operation and Handler (currently `CallbackWrapper` and `TransactionWrapper`) stay in `lib/dex/operation/` but are included in both via `use`.

**Naming internal methods**: The `_modulename_` prefix is required only for methods that end up in `Dex::Operation`'s method table — i.e., wrapper modules mixed into Operation via `include`/`use`. This prevents collisions with user-defined methods in Operation subclasses (e.g., in `RecordWrapper` → `_record_enabled?`, `_record_save!`). Standalone classes that are never mixed into or inherited from Operation (e.g., `AsyncProxy`, `Pipeline`, `Jobs`, `Processor`) use plain method names since there is no collision risk.

Tests are scoped per-area, each area in a separate file. Example: `test/operation/test_params.rb` for testing params.

## Process

When you're done adding a new feature or significantly modifying existing one:
1. Update `README.md` accordingly.
2. Update the corresponding file in `guides/llm/` — these are LLM-optimized docs copied into apps that use dexkit. They must be thorough, compact, accurate, and in sync with implementation. Current files: `guides/llm/OPERATION.md` (includes testing), `guides/llm/EVENT.md` (includes testing), `guides/llm/FORM.md` (includes testing), `guides/llm/QUERY.md` (includes testing).
3. Update `CHANGELOG.md` for any behavior change or new feature. The `[Unreleased]` section must be **consolidated** — it represents the delta from the last release, not a list of commits. If change A is added, then later invalidated by change C, remove A from the changelog entirely. The reader should see only the final state of what changed. **Breaking changes require extra care.** A change is breaking if existing user code, without modification, would behave differently after upgrading — e.g., a callback that previously fired immediately now fires later, a method that returned a value now returns `nil`, or a default that changed. Label these under `### Breaking` (not just `### Changed`) and explain the before/after behavior so users know what to adjust.
4. Update the documentation site in `docs/`. New features must be documented in the appropriate section (`docs/operation/`, `docs/event/`, `docs/form/`, `docs/query/`). New patterns or concepts should also be added to the Introduction page (`docs/guide/introduction.md`). For behavior changes, scan existing documentation pages and update any affected content. Keeping documentation in sync with implementation is critical.

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

### Mongoid test suite

Mongoid tests are **optional** and **not part of the default local run**. Do not run them unless:
- the user explicitly asks for Mongoid coverage, or
- you are working on Mongoid-specific behavior.

Mongoid transaction tests require MongoDB in replica set mode. A standalone `mongod` process is not enough.

Start a temporary local replica set instance (recommended, isolated):

```bash
mkdir -p tmp/mongoid-test-db

mongod \
  --dbpath tmp/mongoid-test-db \
  --replSet rs0 \
  --bind_ip 127.0.0.1 \
  --port 27018 \
  --fork \
  --logpath tmp/mongoid-test.log

mongosh --port 27018 --quiet --eval 'rs.initiate({_id:"rs0",members:[{_id:0,host:"127.0.0.1:27018"}]})' || true
```

Run only Mongoid-focused tests:

```bash
DEX_MONGOID_TESTS=1 \
DEX_MONGODB_URI='mongodb://127.0.0.1:27018/dexkit_test?replicaSet=rs0' \
bundle exec ruby -Itest -e 'Dir["test/operation/test_mongoid_*.rb", "test/query/test_mongoid_*.rb"].sort.each { |file| require File.expand_path(file) }'
```

If needed, run the full suite including Mongoid tests:

```bash
DEX_MONGOID_TESTS=1 \
DEX_MONGODB_URI='mongodb://127.0.0.1:27018/dexkit_test?replicaSet=rs0' \
bundle exec rake test
```

Stop the temporary replica set instance:

```bash
mongosh --port 27018 --quiet --eval 'db.adminCommand({shutdown:1})'
```

**DSL validation:** All DSL methods (`error`, `rescue_from`, `async`, `record`, `advisory_lock`, `before`/`after`/`around`, `transaction`, etc.) validate their arguments at declaration time, raising `ArgumentError` for invalid inputs. The low-level `set` method stays unvalidated — it's the extensible foundation. When adding new DSL methods, always validate arguments early.

## Future Plans

- Performing an operation with nonce token (as used nonce tokens need to be saved somewhere)

## Finishing Up

When work is done, end with a short one-sentence summary appropriate for a commit message.
