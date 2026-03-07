## [Unreleased]

### Breaking

- **Operation record schema refactored** — the `response` column is renamed to `result`, the `error` column is split into `error_code`, `error_message`, and `error_details`, `params` no longer has `default: {}` (nil means "not captured"), and `status` is now `null: false`. The `record response: false` DSL option is now `record result: false`. Status value `done` is renamed to `completed`, and a new `error` status represents business errors via `error!`
- **All outcomes now recorded** — previously, only successful operations were recorded in the sync path. Now business errors (`error!`) record with status `error` and populate `error_code`/`error_message`/`error_details`, and unhandled exceptions record with status `failed`
- **Recording moved outside transaction** — operation records are now persisted outside the database transaction, so error and failure records survive rollbacks. Previously, records were created inside the transaction and would be rolled back alongside the operation's side effects
- **Pipeline order changed** — `RecordWrapper` now runs before `TransactionWrapper` (was after). The pipeline order is now: result → lock → record → transaction → rescue → callback

### Added

- **`error_code`, `error_message`, `error_details` columns** — structured error recording replaces the single `error` string column
- **`once_key` and `once_key_expires_at` columns** — reserved for upcoming idempotency feature (inert until `once` ships)
- **Recommended indexes** — `name`, `status`, and `[:name, :status]` composite index in the migration schema

## [0.6.0] - 2026-03-07

### Added

- **Handler callbacks** — `Dex::Event::Handler` now supports `before`, `after`, and `around` callbacks, same DSL as operations
- **Handler transactions** — `Dex::Event::Handler` supports `transaction` and `after_commit` DSL. Transactions are disabled by default on handlers (opt in with `transaction`)
- **Handler pipeline** — `Dex::Event::Handler` supports `use` for adding custom wrapper modules, same as operations
- **`Dex::Executable`** — shared execution skeleton (Settings, Pipeline, `use` DSL) extracted from Operation and used by both Operation and Handler

### Breaking

- **`transaction false` fully opts out** — operations with `transaction false` no longer route `after_commit` through the database adapter. Previously, `after_commit` on a non-transactional operation would still detect and defer to ambient database transactions (e.g., `ActiveRecord::Base.transaction { op.call }`); now it fires callbacks directly after the pipeline completes. To restore ambient transaction awareness, remove `transaction false` or use `transaction` (enabled)

## 0.5.0 - 2026-03-05

### Added

- **Verified Mongoid support** — operations (transactions, recording, async) and queries now have dedicated Mongoid test coverage running against a MongoDB replica set
- **CI workflow for Mongoid** — GitHub Actions matrix includes a MongoDB replica-set job that runs Mongoid-specific tests

### Breaking

- **`after_commit` now always defers** — non-transactional operations queue callbacks in memory and flush them after the operation pipeline succeeds, matching the behavior of transactional operations. Previously, `after_commit` fired immediately inline when no transaction was active — code that relied on immediate execution (e.g., reading side effects of the callback later in `perform`) must account for the new deferred timing. Callbacks are discarded on `error!` or exception. Nested operations flush once at the outermost successful boundary. Ambient database transactions (e.g., `ActiveRecord::Base.transaction { op.call }`) are still respected via the adapter.

### Fixed

- **Mongoid async recording** — `record_id` is now serialized with `.to_s` so BSON::ObjectId values pass through ActiveJob correctly
- **Mongoid transaction adapter** — simplified nesting logic; the outermost `Mongoid.transaction` block now reliably owns callback flushing, fixing edge cases where nested rollbacks could leak callbacks

## [0.4.1] - 2026-03-04

### Added

- **`after_commit` in operations** — `after_commit { ... }` defers a block until the surrounding database transaction commits
  - ActiveRecord adapter uses `ActiveRecord.after_all_transactions_commit` (requires Rails 7.2+)
  - Mongoid adapter manually tracks callbacks and fires them after the outermost `Mongoid.transaction` commits
  - If called outside a transaction, the block executes immediately

## [0.4.0] - 2026-03-04

### Added

- **Query objects** — `Dex::Query` base class for encapsulating database queries with filtering, sorting, and parameter binding
  - Typed properties via `prop`/`prop?` DSL (same as Operation and Event)
  - `scope { Model.all }` DSL for declaring the base scope
  - **Filter DSL** — `filter :name, :strategy` with built-in strategies: `eq`, `not_eq`, `contains`, `starts_with`, `ends_with`, `gt`, `gte`, `lt`, `lte`, `in`, `not_in`
  - Custom filter blocks: `filter(:name) { |scope, value| ... }`
  - Optional filters (nilable props) are automatically skipped when `nil`
  - **Sort DSL** — `sort :col1, :col2` for column sorts with automatic `asc`/`desc` via `"-col"` prefix convention
  - Custom sort blocks: `sort(:name) { |scope| ... }`
  - Default sort: `sort :name, default: "-created_at"`
  - **Backend adapters** for both ActiveRecord and Mongoid (auto-detected from scope)
  - `scope:` injection for pre-scoping (e.g., `current_user.posts`)
  - `from_params` for binding from controller params with automatic type coercion and sort validation
  - `to_params` for round-tripping query state back to URL params
  - `param_key` DSL for customizing the params namespace
  - ActiveModel::Naming / ActiveModel::Conversion for Rails form compatibility
  - Convenience class methods: `.call`, `.count`, `.exists?`, `.any?`
  - Inheritance support — filters, sorts, and scope are inherited by subclasses
- `Dex::Match` is now included in `Dex::Form` — `Ok`/`Err` are available without prefix inside forms

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

### Changed

- `Dex::Match` is now included in `Dex::Operation` – `Ok`/`Err` are available without prefix inside operations. External contexts (controllers, POROs) can still use `Dex::Ok`/`Dex::Err` or `include Dex::Match`.

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
