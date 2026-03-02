## [Unreleased]

## [0.2.0] - 2026-03-02

### Added

- **Event system** — typed, immutable event value objects with publish/subscribe
  - Typed properties via `prop`/`prop?` DSL (same as Operation)
  - Sync and async publishing (`event.publish`, `Event.publish(sync: true)`)
  - Handler DSL: `on` for subscription, `retries` with exponential/fixed/custom backoff
  - Async dispatch via ActiveJob (`Dex::Event::Processor`, lazy-loaded)
  - Causality tracing: `event.trace { ... }` and `caused_by:` link events into chains with shared `trace_id`
  - Block-scoped suppression: `Dex::Event.suppress(SomeEvent) { ... }`
  - Optional persistence via `event_store` configuration
  - Context capture and restoration across async boundaries (`event_context`, `restore_event_context`)
- **Event test helpers** — `Dex::Event::TestHelpers` module
  - `capture_events` block for inspecting published events without dispatching
  - `assert_event_published`, `refute_event_published`, `assert_event_count`
  - `assert_event_trace`, `assert_same_trace` for causality assertions

### Fixed

- `_Array(_Ref(...))` props now serialize and deserialize correctly in both Operation and Event (array of model references was crashing on `value.id` called on Array)

### Changed

- Extracted `Dex::TypeCoercion` — shared module for prop serialization and coercion, used by both Operation and Event. Eliminates duplication of `_serialized_coercions`, ref type detection, and value coercion logic.
- Extracted `Dex::PropsSetup` — shared `prop`/`prop?`/`_Ref` DSL wrapping Literal's with reserved name validation, public reader default, and automatic RefType coercion. Eliminates duplication between Operation and Event.

## [0.1.0] - 2026-03-01

- Initial public release
- **Operation** base class with typed properties (via `literal` gem), structured errors, and Ok/Err result pattern
- Contract DSL: `success` and `error` declarations with runtime validation
- Safe execution: `.safe.call` returns Ok/Err instead of raising
- Rescue mapping: `rescue_from` to convert exceptions into typed errors
- Callbacks: `before`, `after`, `around` lifecycle hooks
- Async execution via ActiveJob (`async` DSL)
- Transaction support for ActiveRecord and Mongoid
- Advisory locking via `with_advisory_lock` gem
- Operation recording (persistence of execution results to DB)
- `Dex::RefType` — model reference type with automatic `find` coercion
- **Test helpers**: `call_operation`, `call_operation!`, result/contract/param assertions, async and transaction assertions, batch assertions
- **Stubbing & spying**: `stub_operation`, `spy_on_operation`
- **TestLog**: global activity log for test introspection
