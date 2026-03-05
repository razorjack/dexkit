# Testing Events

## Setup

```ruby
# test/test_helper.rb
require "dex/event_test_helpers"

class Minitest::Test
  include Dex::Event::TestHelpers
end
```

## Capturing events

Capture published events without dispatching handlers:

```ruby
def test_publishes_order_placed
  capture_events do
    Order::Placed.publish(order_id: 1, total: 99.99)

    assert_event_published(Order::Placed)
    assert_event_published(Order::Placed, order_id: 1)
    refute_event_published(Order::Cancelled)
  end
end
```

Outside `capture_events`, events dispatch synchronously (test safety).

## Assertions

### Published events

```ruby
assert_event_published(Order::Placed)                    # at least one
assert_event_published(Order::Placed, order_id: 1)       # with matching props
refute_event_published                                  # nothing published at all
refute_event_published(Order::Cancelled)                  # specific class not published
```

### Count

```ruby
assert_event_count(Order::Placed, 2)
```

### Trace assertions

```ruby
assert_event_trace(parent, child)          # child.caused_by_id == parent.id
assert_same_trace(event_a, event_b)        # all share same trace_id
```

## Suppression in tests

Suppress events when testing code that publishes as a side effect:

```ruby
def test_creates_order_without_events
  Dex::Event.suppress do
    order = Order::Place.call(item_id: 1)
    assert order.persisted?
  end
end
```

## Complete example

```ruby
class Order::PlaceTest < Minitest::Test
  include Dex::Event::TestHelpers

  def test_publishes_order_placed
    capture_events do
      order = Order::Place.call(item_id: 1, quantity: 2)

      assert_event_published(Order::Placed, order_id: order.id)
      assert_event_count(Order::Placed, 1)
      refute_event_published(Order::Cancelled)
    end
  end

  def test_causality_chain
    capture_events do
      parent = Order::Placed.new(order_id: 1, total: 99.99)

      parent.trace do
        Shipment::Reserved.publish(order_id: 1)
      end

      child = _dex_published_events.last
      assert_event_trace(parent, child)
      assert_same_trace(parent, child)
    end
  end
end
```
