## [Unreleased]

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
