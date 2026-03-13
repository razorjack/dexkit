---
description: "Generate Stripe-style prefixed IDs with Dex::Id – k-sortable, human-readable, and collision-resistant identifiers for Rails models."
---

# Stripe-Style IDs

`Dex::Id` generates Stripe-style prefixed identifiers – compact, human-readable, and sortable by creation time.

```ruby
Dex::Id.generate("ord_")
# => "ord_2GvZx8KpaBcDeFgHjKmN"
```

dexkit uses `Dex::Id` internally for operation IDs (`op_`), event IDs (`ev_`), trace IDs (`tr_`), and handler execution IDs (`hd_`). The generator is a general-purpose utility available for your own models and domain objects.

## Generate

```ruby
Dex::Id.generate("ord_")
# => "ord_2GvZx8KpaBcDeFgHjKmN"
#     |   |          |
#     |   |          └── 12 chars random (base58)
#     |   └── 8 chars timestamp (base58-encoded milliseconds)
#     └── prefix
```

The prefix must be lowercase alphanumeric (with internal underscores allowed), ending in an underscore:

```ruby
Dex::Id.generate("ord_")              # ok
Dex::Id.generate("order_item_")       # ok – internal underscores are fine
Dex::Id.generate("v2_order_")         # ok

Dex::Id.generate("Op_")              # ArgumentError – uppercase not allowed
Dex::Id.generate("ord")              # ArgumentError – must end with _
```

### Random width

The `random:` option controls the width of the random suffix. Default is 12, minimum is 8.

```ruby
Dex::Id.generate("ord_")              # 8 timestamp + 12 random = 20-char payload
Dex::Id.generate("ord_", random: 8)   # 8 timestamp + 8 random  = 16-char payload
Dex::Id.generate("ord_", random: 16)  # 8 timestamp + 16 random = 24-char payload
```

The default is right for virtually all use cases. See [Collision resistance](#collision-resistance) for guidance on when shorter widths are safe.

## Parse

Parse an ID back into its components:

```ruby
parsed = Dex::Id.parse("ord_2GvZx8KpaBcDeFgHjKmN")
parsed.prefix     # => "ord_"
parsed.created_at # => 2026-03-13 14:22:33.421 UTC
parsed.random     # => "aBcDeFgHjKmN"
```

`parse` returns a `Dex::Id::Parsed` value object (a `Data.define`) with three fields: `prefix`, `created_at` (UTC `Time`), and `random`.

Parsing works for any prefix format – it finds the last `_` in the string and uses that as the prefix boundary (`_` is not in the base58 alphabet).

Invalid input raises `ArgumentError`:

```ruby
Dex::Id.parse("abc123")         # no underscore – can't determine prefix
Dex::Id.parse("ord_12345678")   # payload too short
Dex::Id.parse("ord_0000000000") # '0' is not a base58 character
```

## Properties

**Base58 alphabet** – `123456789ABCDEFGH...xyz`. No `0`/`O`/`I`/`l`, so IDs are safe for copy-paste and verbal communication.

**K-sortable** – the alphabet is in ASCII order, so IDs with the same prefix sort roughly chronologically via plain string comparison. IDs created in the same millisecond are ordered by random suffix (arbitrary), and clock adjustments or multi-host skew can cause minor reordering. For strict ordering, use a dedicated timestamp column.

**Millisecond precision** – timestamps use `Process.clock_gettime(CLOCK_REALTIME, :millisecond)`.

**Long runway** – base58^8 milliseconds covers approximately 4,050 years.

## Collision resistance

Each millisecond has its own independent random space. With the default 12 random chars, that's 58^12 (~1.4 x 10^21) combinations per millisecond.

| `random:` | Space per ms | Collisions/year at 1 ID/ms | Collisions/year at 10 IDs/ms |
|---|---|---|---|
| 8 | 58^8 (~1.28 x 10^14) | ~0.00012 | ~0.012 |
| 12 (default) | 58^12 (~1.45 x 10^21) | ~0.000000000011 | ~0.0000000011 |

**The default is more than sufficient for any realistic workload.** Even at 1,000 IDs per millisecond (a rate most applications never approach), the expected collision rate is negligible.

`random: 8` is safe for low-to-moderate throughput – typical web apps generating a few IDs per request. For high-throughput batch ID generation (hundreds of IDs per millisecond), use the default 12 or higher.

### Compared to UUIDv4

UUIDv4 has more raw random bits (122 vs ~70), but all UUIDs share a single global pool, while `Dex::Id` partitions randomness by millisecond. Both are astronomically safe for any real application. `Dex::Id` trades some collision-resistance headroom for time-sortability, human-readable prefixes, and better B-tree index performance (sequential inserts instead of random page splits).

## Recipes

### ActiveRecord – string primary key

```ruby
class Order < ApplicationRecord
  before_create { self.id ||= Dex::Id.generate("ord_") }
end
```

Requires a string primary key column in your migration:

```ruby
create_table :orders, id: :string do |t|
  # ...
end
```

### Mongoid

```ruby
class Order
  include Mongoid::Document

  field :_id, type: String, default: -> { Dex::Id.generate("ord_") }
end
```

### External reference (not a primary key)

```ruby
class Shipment < ApplicationRecord
  before_create { self.tracking_id ||= Dex::Id.generate("shp_") }
end
```

### Debugging

```ruby
Dex::Id.parse(order.id).created_at
# => 2026-03-13 14:22:33.421 UTC
```

## Trade-offs

Time-sortable IDs reveal creation time to anyone holding the ID. Two IDs from the same prefix reveal relative ordering and time gap. At scale, this leaks creation rate and volume. For most applications this is a feature, not a bug – Stripe uses this pattern everywhere.

For applications with genuine privacy requirements around creation timing (HIPAA, GDPR-adjacent, defense in depth), use `SecureRandom.uuid` with a manual prefix instead.
