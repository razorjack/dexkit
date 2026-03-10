## [Unreleased]

### Breaking

- **Mongoid transaction handling is now explicit and Dex-managed** — Dex no longer auto-detects Mongoid as the default transaction adapter when `Mongoid` is merely loaded, and `after_commit` no longer runs early inside an ambient `Mongoid.transaction` opened outside Dex. Before: a Mongoid-only app could start wrapping operations in `Mongoid.transaction` implicitly, and `after_commit` inside an external Mongoid transaction could fire before the real commit, leaking side effects on rollback. After: ActiveRecord is still auto-detected, but Mongoid transactions require `Dex.configure { |c| c.transaction_adapter = :mongoid }` or `transaction :mongoid`, and `after_commit` in Mongoid must run inside a Dex-managed transaction or be replaced with `after`
- **Recording backends now validate required attributes before use** — Dex no longer silently drops missing `params`, `result`, `status`, or `once` attributes from `record_class`. Before: partial ActiveRecord/Mongoid recording models could appear to work while losing status transitions, replay data, or async params. After: Dex raises `ArgumentError` naming the missing attributes required by core recording, async record jobs, or `once`. Apps using minimal recording models must add the required columns/fields or explicitly disable the features that need them

### Fixed

- **Mongoid-only Rails compatibility hardening** — Dex now boots and runs cleanly in Mongoid-only Rails apps without `activerecord` loaded, with prescriptive `LoadError`s for unsupported or missing-runtime paths such as `advisory_lock`, `transaction :mongoid` without Mongoid loaded, and async event dispatch without `ActiveJob`. Coverage now includes clean-process Mongoid-only boot probes and a dedicated no-ActiveRecord runtime suite against MongoDB
- **Mongoid async/recording serialization** — `_Ref(Model)` now serializes IDs via `id.as_json`, so `BSON::ObjectId` values round-trip through async operations, async events, and recording without `ActiveJob::SerializationError`. Recording and `once` also sanitize untyped Mongoid document results to JSON-safe payloads so replay/async status transitions complete correctly
- **Mongoid query and form parity** — query adapter detection and scope merging now normalize Mongoid association scopes to `Mongoid::Criteria`, uniqueness validation now excludes persisted Mongoid records correctly and uses a case-insensitive regex path for `case_sensitive: false`, and `_Ref(lock: true)` now fails fast for model classes that do not support `.lock`
- **Mongoid transaction callback isolation** — Dex now uses fiber-local callback queues and prefers Mongoid's public transaction-state API before falling back to thread internals, reducing callback leakage across fibers and making ambient transaction detection less coupled to Mongoid internals

## [0.8.0] - 2026-03-09

### Added

- **Registry** — `Dex::Operation.registry`, `Dex::Event.registry`, and `Dex::Event::Handler.registry` return frozen Sets of all named subclasses. Populated automatically via `inherited`; anonymous and stale (unreachable after code reload) classes are excluded. `deregister(klass)` removes entries. `clear!` empties the registry. Zeitwerk-compatible — registries reflect loaded classes; eager-load to get the full list
- **Description & prop descriptions** — `description "text"` class-level DSL for operations and events. `desc:` keyword on `prop`/`prop?` for per-property descriptions (validated as String). Both appear in `contract.to_h`, `to_json_schema`, and `explain` output. Optional — no error or warning when omitted
- **`contract.to_h` export** — serializes the full operation contract to a plain Ruby Hash: `name`, `description`, `params` (with typed strings and `desc`), `success`, `errors`, `guards`, `context`, `pipeline`, `settings`. Types are human-readable strings (`"String"`, `"Integer(1..)"`, `"Ref(Product)"`, `"Nilable(String)"`). Omits nil/empty fields
- **`contract.to_json_schema` export** — generates JSON Schema (Draft 2020-12) from the operation contract. Default section is `:params` (input schema for LLM tools, form generation, API validation). Also supports `:success`, `:errors`, and `:full` sections
- **Event export** — `Event.to_h` and `Event.to_json_schema` class methods for serializing event definitions. Same type serialization as operations
- **Handler export** — `Handler.to_h` returns name, events (array), retries, transaction, and pipeline metadata. `handled_events` returns all subscribed event classes
- **Bulk export** — `Dex::Operation.export(format: :hash|:json_schema)`, `Dex::Event.export(format: :hash|:json_schema)`, `Dex::Event::Handler.export(format: :hash)`. Returns arrays sorted by name — directly serializable with `JSON.generate`
- **`Dex::Tool` — ruby-llm integration** — bridges dexkit operations to [ruby-llm](https://rubyllm.com/) tools. `Dex::Tool.from(Op)` generates a `RubyLLM::Tool` from an operation's contract. `Dex::Tool.all` converts all registered operations. `Dex::Tool.from_namespace("Order")` filters by namespace. `Dex::Tool.explain_tool` provides a built-in preflight check tool. Lazy-loaded — ruby-llm is only required when you call `Dex::Tool`
- **`Dex::TypeSerializer`** — converts Literal types to human-readable strings and JSON Schema. Handles `String`, `Integer`, `Float`, `Boolean`, `Symbol`, `Hash`, `Date`, `Time`, `DateTime`, `BigDecimal`, `_Nilable`, `_Array`, `_Union`, `_Ref`, and range-constrained types (`_Integer(1..)`)
- **Rake task `dex:export`** — `rake dex:export` with `FORMAT=hash|json_schema`, `SECTION=operations|events|handlers`, `FILE=path` environment variables. Auto-loaded via Railtie in Rails apps
- **Rake task `dex:guides`** — `rake dex:guides` installs LLM-optimized guides as `AGENTS.md` files in app directories (`app/operations/`, `app/events/`, `app/event_handlers/`, `app/forms/`, `app/queries/`). Only writes to directories that exist. Stamps each file with the installed dexkit version. The event guide is installed to both `app/events/` and `app/event_handlers/` when either exists. Existing hand-written `AGENTS.md` files are detected and skipped (`FORCE=1` to overwrite). Override paths with `OPERATIONS_PATH`, `EVENTS_PATH`, `EVENT_HANDLERS_PATH`, `FORMS_PATH`, `QUERIES_PATH` environment variables
- **`explain` includes `description`** — `explain` output now contains `:description` when set on the operation
- **`explain` class method for operations** — `MyOp.explain(**kwargs)` returns a frozen Hash with the full preflight state: resolved props, context source tracking (`:explicit`/`:ambient`/`:default`), per-guard pass/fail results with messages, once key and status (`:fresh`/`:exists`/`:expired`/`:pending`/`:invalid`/`:misconfigured`/`:unavailable`), advisory lock key, record/transaction/rescue/callback settings, pipeline steps, and overall `callable` verdict (accounts for both guard failures and once blocking statuses). No side effects — `perform` is never called. Gracefully handles invalid props — returns partial results with `error` key instead of raising, class-level information always available. Respects pipeline customization — removed steps report inactive. Custom middleware can contribute via `_name_explain` class methods

### Breaking

- **`contract.to_h` returns rich format** — `contract.to_h` now returns a comprehensive serialized Hash with string-typed params, description, context, pipeline, and settings instead of the raw `Data#to_h` shape. Before: `contract.to_h[:success]` returned `String` (the class). After: it returns `"String"` (a string). Code doing type comparisons like `contract.to_h[:success] == String` must update to use `contract.success` (which still returns raw types) or compare against `"String"`. The raw Ruby types remain accessible via `contract.params`, `contract.success`, `contract.errors`, `contract.guards`
- **`_Ref` JSON Schema type changed from `"integer"` to `"string"`** — `_Ref(Model)` now serializes as `{ type: "string" }` in JSON Schema. IDs are treated as opaque strings to support Mongoid BSON::ObjectId, UUIDs, and other non-integer primary key formats. Code that relied on `type: "integer"` for Ref params must update

### Fixed

- **`Handler.deregister` now unsubscribes from Bus** — `Dex::Event::Handler.deregister(klass)` removes the handler from both the registry and the event Bus. Previously, deregistered handlers remained subscribed and would still fire on published events
- **Registry prunes stale entries** — `registry` now removes unreachable class references from the backing Set during each call, preventing memory leaks from code reload cycles
- **`description(false)` and `desc: false` now raise `ArgumentError`** — previously accepted as "missing" values due to falsey evaluation. Both DSL methods now validate with `!text.nil?` / `!desc.nil?` to enforce the String requirement, matching the library's fail-fast convention
- **`prop_descriptions` no longer leaks parent descriptions for redeclared props** — when a child class redefines a prop without `desc:`, the parent's description is cleared instead of being inherited. Providing a new `desc:` on the child works as before
- **Rake task validates handler format** — `rake dex:export SECTION=handlers FORMAT=json_schema` now raises a clear error instead of hitting `Handler.export`'s `ArgumentError`

## [0.7.0] - 2026-03-08

### Breaking

- **Operation record schema refactored** — the `response` column is renamed to `result`, the `error` column is split into `error_code`, `error_message`, and `error_details`, `params` no longer has `default: {}` (nil means "not captured"), and `status` is now `null: false`. The `record response: false` DSL option is now `record result: false`. Status value `done` is renamed to `completed`, and a new `error` status represents business errors via `error!`
- **All outcomes now recorded** — previously, only successful operations were recorded in the sync path. Now business errors (`error!`) record with status `error` and populate `error_code`/`error_message`/`error_details`, and unhandled exceptions record with status `failed`
- **Recording moved outside transaction** — operation records are now persisted outside the database transaction, so error and failure records survive rollbacks. Previously, records were created inside the transaction and would be rolled back alongside the operation's side effects
- **Pipeline order changed** — `RecordWrapper` now runs before `TransactionWrapper` (was after). The pipeline order is now: result → once → lock → record → transaction → rescue → guard → callback
- **`Operation.contract` shape changed** — `Contract` gains a fourth field `:guards`. Code using positional destructuring (`in Contract[params, success, errors]`) must be updated to include the new field. Keyword-based access (`.params`, `.errors`, etc.) is unaffected

### Added

- **Ambient context** — `Dex.with_context(current_user: user) { ... }` sets fiber-local ambient state. The `context` DSL on operations and events maps props to ambient keys, auto-filling them when not passed explicitly. Explicit kwargs always win. Works with guards (`callable?`), events (captured at publish time), and nested operations. Introspection via `context_mappings`
- **`guard` DSL for precondition checks** — named, inline preconditions that detect threats (conditions under which the operation should not proceed). Guards auto-declare error codes, support dependencies (`requires:`), collect all independent failures, and skip dependent guards when a dependency fails. `callable?` and `callable` class methods check guards without running `perform` – useful for UI show/hide, disabled buttons with reasons, and API pre-validation. Contract introspection via `contract.guards`. Test helpers: `assert_callable`, `refute_callable`
- **`once` DSL for operation idempotency** — ensures an operation executes at most once for a given key, replaying stored results on subsequent calls. Supports prop-based keys (`once :order_id`), composite keys, block-based custom keys, call-site keys (`.once("key")`), optional expiry (`expires_in:`), and `clear_once!` for key management. Business errors are replayed; exceptions release the key for retry. Works with `.safe.call` and `.async.call`
- **`error_code`, `error_message`, `error_details` columns** — structured error recording replaces the single `error` string column
- **Recommended indexes** — `name`, `status`, `[:name, :status]` composite index, and unique partial index on `once_key` in the migration schema

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
