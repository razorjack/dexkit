dexkit. Module name: `Dex`

Ruby library providing base classes for service/operation, event, and form object patterns in Rails apps.

## Pre-1.0 Policy

dexkit is pre-1.0. Backwards compatibility is not a concern. There is no migration path obligation between versions. Redundant features, mediocre APIs, and even good features should be removed without hesitation if replaced by a great feature that does the same thing better. Be bold in design decisions — backwards compatibility considerations must not slow down development while we're pre-1.0.

## Design Philosophy

The public API is the product. The internals are the engineering. Never sacrifice DX for implementation convenience — but never sacrifice correctness for a prettier surface. When these forces conflict, find a design that satisfies both. If forced to choose: correctness wins, then find a way to make the correct thing beautiful.

## Core Values

### API — what users see

1. **Beautiful Ruby API** — must read and feel good. The DSL is the first thing users encounter and the reason they stay.
2. **Short over verbose, but unambiguous** — naming should be compact yet clear. `Dex::Tool` not `Dex::OperationToRubyLLMMapper`. `error!` not `raise_business_error!`.
3. **Batteries included, opt-out possible** — sensible defaults that work without configuration. Every default is overridable.
4. **Consistency across primitives** — Operation, Event, Form, Query should feel like one library. Same concept, same word, same behavior. If Operation has `prop`, Event has `prop`.
5. **Progressive disclosure** — the 80% use case requires zero configuration. Complex cases are possible without contortion.

### Engineering — what we build

6. **Fail fast, fail loud** — invalid inputs, undeclared codes, type mismatches raise immediately. No silent failures.
7. **Prescriptive error messages** — every error tells the user what they did, why it's wrong, and what to do instead. Include the class name, the invalid value, and the valid options. `"Orders::Place declares unknown error code :not_found. Declared codes: [:out_of_stock, :payment_failed]"` — not just `"unknown error code"`.
8. **Declare intent, enforce mechanically** — contracts are declared at the class level and enforced at runtime. Rules live in code, not in documentation.
9. **Own the mechanics, not the domain** — Dex decides pipeline order, when callbacks fire, how transactions wrap, where recording happens. It never decides what a valid order is or how to charge a payment. `perform` is the user's territory.
10. **Defend boundaries, trust internals** — validate at every public entry point (DSL methods, `new`, `call`). Inside the implementation, trust that validated data is correct. Deep-copy mutable state when exposing it through public readers.
11. **Isolate state** — fiber-local storage, no global mutation, `ensure` blocks for cleanup. Every `push` has a `pop`. Every state change is reversible on error.

## API Design

**DSL methods are declarations, not commands.** `error :not_found` declares an error code. `transaction true` declares transactional behavior. They read as "this operation *is*" not "do this."

**Kwargs over positional for 2+ arguments.** `record result: false` not `record(false, true)`. Single boolean/symbol arguments are fine positional: `transaction false`, `async :sidekiq`.

**Blocks for behavior, values for configuration.** `guard :insufficient_funds, "message" do ... end` (behavior) vs `transaction true` (configuration).

**One mechanism per concern.** If there are two ways to set a value (explicit kwarg + implicit context), that's acceptable — two clear mechanisms with distinct roles. Three overlapping ways is one too many. Remove the weakest.

## Implementation Standards

- **Validate at entry, not deep inside.** DSL methods validate arguments at declaration time. Public methods validate at the top. Internal methods trust their callers.
- **Deep-copy mutable state on public readers.** Methods that return internal state (trace stacks, frame arrays, context hashes) return copies. Internal methods can read `_state` directly.
- **`ensure` for cleanup.** Every `push` must have a `pop` in `ensure`. Every fiber-local write must have a restore path. No relying on happy-path cleanup.
- **Graceful degradation for optional infrastructure.** The `safe_attributes` pattern: if a DB column or optional feature isn't available, silently omit it. Core functionality works without optional dependencies.
- **No ambient coupling.** Don't read from fiber keys you didn't define. If module A needs data from module B, pass it explicitly or go through a shared module (like `Dex::Trace`).

## Testing

**Tests read like examples** — succinct, no bloat. A new user should be able to understand a feature by reading its test file.

**Every DSL method gets a positive and negative test.** `error :foo` works; `error 123` raises `ArgumentError` with the expected message.

**Test the error messages.** `assert_match /declared codes/, error.message` — the message *is* the DX when something breaks.

**Integration over isolation for wrappers.** A wrapper is meaningless in isolation. Test it through `Operation#call`.

**Edge cases are first-class.** Nil inputs, empty collections, missing columns, concurrent access patterns. Not afterthoughts.

Tests are scoped per-area, each area in a separate file. Example: `test/operation/test_params.rb` for testing params.

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
    context_dsl.rb       # Dex::ContextDSL (shared context DSL base module)
    context_setup.rb     # Dex::ContextSetup (context DSL + injection for Operation + Event)
    error.rb             # Dex::Error
    operation_failed.rb  # Dex::OperationFailed (async infrastructure crash exception)
    timeout.rb           # Dex::Timeout (wait! deadline exceeded exception)
    settings.rb          # Dex::Settings (set, settings_for, validate_options!)
    pipeline.rb          # Dex::Pipeline (shared execution pipeline)
    executable.rb        # Dex::Executable (shared skeleton: Settings, Pipeline, use DSL)
    registry.rb          # Dex::Registry (shared subclass registry for Operation, Event, Handler)
    type_serializer.rb   # Dex::TypeSerializer (type → string and type → JSON Schema)
    id.rb                # Dex::Id (Stripe-style prefixed ID generator)
    trace.rb             # Dex::Trace (unified fiber-local trace stack)
    match.rb             # Dex::Ok, Dex::Err aliases + Dex::Match
    tool.rb              # Dex::Tool (ruby-llm integration, lazy-loaded)
    railtie.rb           # Dex::Railtie (rake tasks, auto-loaded in Rails)
    operation.rb         # Operation class orchestrator (requires all parts)
    operation/
      trace_wrapper.rb   # Dex::TraceWrapper
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
      transaction_adapter.rb # Operation::TransactionAdapter (ActiveRecord adapter)
      jobs.rb            # const_missing + lazy DirectJob/RecordJob
      ticket.rb          # Dex::Operation::Ticket (async handle, outcome reconstruction, wait/wait!)
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
      context.rb         # Dex::Form::Context (context DSL + ActiveModel attribute check)
      export.rb          # Dex::Form::Export (to_h, to_json_schema)
      nesting.rb         # Dex::Form::Nesting (nested_one, nested_many DSL)
      uniqueness_validator.rb # Dex::Form::UniquenessValidator (validates :x, uniqueness: true)
    query.rb             # Query class orchestrator (requires all parts)
    query/
      backend.rb         # Dex::Query::Backend (AR + Mongoid adapters, strategy implementations)
      export.rb          # Dex::Query::Export (to_h, to_json_schema)
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
  tool/
    test_*.rb            # Per-feature tool test files
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

## Process

When you're done adding a new feature or significantly modifying existing one:
1. Update `README.md` accordingly.
2. Update the corresponding file in `guides/llm/` — these are LLM-optimized docs copied into apps that use dexkit. They must be thorough, compact, accurate, and in sync with implementation. Current files: `guides/llm/OPERATION.md` (includes testing), `guides/llm/EVENT.md` (includes testing), `guides/llm/FORM.md` (includes testing), `guides/llm/QUERY.md` (includes testing), `guides/llm/TOOL.md` (Operation + Query tool integration).
3. Update `CHANGELOG.md` for any behavior change or new feature. The `[Unreleased]` section must be **consolidated** — it represents the delta from the last release, not a list of commits. If change A is added, then later invalidated by change C, remove A from the changelog entirely. The reader should see only the final state of what changed. **Breaking changes require extra care.** A change is breaking if existing user code, without modification, would behave differently after upgrading — e.g., a callback that previously fired immediately now fires later, a method that returned a value now returns `nil`, or a default that changed. Label these under `### Breaking` (not just `### Changed`) and explain the before/after behavior so users know what to adjust.
4. Update the documentation site in `docs/`. New features must be documented in the appropriate section (`docs/operation/`, `docs/event/`, `docs/form/`, `docs/query/`, `docs/tool/`). New patterns or concepts should also be added to the Introduction page (`docs/guide/introduction.md`). For behavior changes, scan existing documentation pages and update any affected content. Keeping documentation in sync with implementation is critical.

## Code Quality

**Clean output is mandatory.** Every check — tests, rubocop, markdown rubocop — must produce zero warnings, zero errors, and zero extraneous noise. Work is not done until the output is clean. If a check emits unexpected output (deprecation warnings, Ruby warnings, noisy gems, spurious stderr), investigate and fix the root cause. Do not ignore it, do not suppress it with redirects, do not leave it for later.

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

Mongoid tests run against a standalone `mongod` instance (no replica set required — Dex does not manage Mongoid transactions).

Run only Mongoid-focused tests:

```bash
DEX_MONGOID_TESTS=1 \
bundle exec ruby -Itest -e 'Dir["test/operation/test_mongoid_*.rb", "test/query/test_mongoid_*.rb"].sort.each { |file| require File.expand_path(file) }'
```

If needed, run the full suite including Mongoid tests:

```bash
DEX_MONGOID_TESTS=1 \
bundle exec rake test
```

**DSL validation:** All DSL methods (`error`, `rescue_from`, `async`, `record`, `advisory_lock`, `before`/`after`/`around`, `transaction`, etc.) validate their arguments at declaration time, raising `ArgumentError` for invalid inputs. The low-level `set` method stays unvalidated — it's the extensible foundation. When adding new DSL methods, always validate arguments early.

## Finishing Up

When work is done, end with a short one-sentence summary appropriate for a commit message.
