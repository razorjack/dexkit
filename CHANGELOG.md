## [Unreleased]
## [0.3.0] - 2026-03-03

### Added

- **Form objects** — `Dex::Form` base class for user-facing input handling
  - Typed attributes via ActiveModel (`attribute :name, :string`)
  - Normalization on assignment (`normalizes :email, with: -> { _1&.strip&.downcase }`)
  - Full ActiveModel validation support, including custom `uniqueness` validator with scope, case-insensitive matching, conditions, and record exclusion
  - `model` DSL for binding a form to an ActiveRecord model class (drives `model_name`, `persisted?`, `to_key`, `to_param`)
  - `record` reader and `with_record` chainable method for edit/update forms — record is excluded from form attributes and protected from mass assignment
  - `nested_one` / `nested_many` DSL for nested form objects with auto-generated constants, `build_` methods, and `_attributes=` setters
  - Hash coercion, Rails numbered hash format, and `_destroy` filtering in nested forms
  - Validation propagation from nested forms with prefixed error keys (`address.street`, `documents[0].doc_type`)
  - `ActionController::Parameters` support — strong parameters (`permit`) not required; the form's attribute declarations are the whitelist
  - `to_h` / `to_hash` serialization including nested forms
  - `ValidationError` for bang-style save patterns
  - Full Rails `form_with` / `fields_for` compatibility
- **Form uniqueness validator** — `validates :email, uniqueness: true`
  - Model resolution chain: explicit `model:` option, `model` DSL, or infer from class name (`UserForm` → `User`)
  - Options: `scope`, `case_sensitive`, `conditions` (zero-arg or form-arg lambda), `attribute` mapping, `message`
  - Excludes current record via model's `primary_key` (not hardcoded `id`)
  - Declaration-time validation of `model:` and `conditions:` options
- Added `actionpack` as development dependency for testing Rails controller integration
- Added `activemodel >= 6.1` as runtime dependency

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

### Changed

- Extracted shared `validate_options!` helper for DSL option validation
- Added `Dex.warn` for unified warning logging
- Added `Dex::Concern` to reduce module inclusion boilerplate
- Simplified internal method names in standalone classes (AsyncProxy, Pipeline, Jobs, Processor)

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
