# Stock Reservation Logic

## Stock Concept

Stock is stored per warehouse-product combination in `inventory_items`.

| Field | Meaning |
|-------|---------|
| `on_hand_quantity` | Physical items available in the warehouse |
| `reserved_quantity` | Items currently held for unpaid/reviewed orders |
| `available_quantity` | Calculated as `on_hand_quantity - reserved_quantity` |

Database constraints:

```sql
on_hand_quantity >= 0
reserved_quantity >= 0
reserved_quantity <= on_hand_quantity
```

## Available Quantity

```text
available_quantity = on_hand_quantity - reserved_quantity
```

An order can only reserve stock when:

```text
available_quantity >= requested_quantity
```

## Reservation

When a buyer creates an order:

```mermaid
flowchart TD
    A[Find selected or auto-chosen warehouse] --> B[Confirm inventory_items.warehouse_id + product_id]
    B --> C{available_quantity >= requested?}
    C -->|Yes| D[Increment reserved_quantity atomically]
    D --> E[Refresh row and re-check<br/>reserved_quantity <= on_hand_quantity]
    E --> F[Create StockMovement movement_type = reserved]
    F --> G[Create Order and OrderItem<br/>in same transaction]
    C -->|No| H[409 Conflict]
```

### Reservation Stock Movement

```text
StockMovement
  movement_type = reserved
  quantity = ordered quantity
  order_id = order id
  idempotency_key = order-specific unique key
```

## Automatic Warehouse Selection

If the buyer uses auto-selection:

```mermaid
flowchart TD
    A[Search active warehouses for requested product] --> B{Row with highest<br/>available_quantity?}
    B --> C{available_quantity >= requested?}
    C -->|Yes| D[Proceed with reservation]
    C -->|No| E[No warehouse available]
```

## Payment Verification - Stock Sold

When admin verifies payment:

```mermaid
flowchart TD
    A[For each order item] --> B[Decrement reserved_quantity by item qty]
    B --> C[Decrement on_hand_quantity by item qty]
    C --> D[Create StockMovement movement_type = sold]
    D --> E[Update order.status = paid]
    E --> F[Send paid confirmation email]
```

Net stock effect:

```text
reserved_quantity -= qty
on_hand_quantity -= qty
available_quantity stays consistent because both sides decrease by qty
```

## Rejection - Stock Released

When admin rejects payment:

```mermaid
flowchart TD
    A[For each order item] --> B[Decrement reserved_quantity by item qty]
    B --> C[Create StockMovement movement_type = released]
    C --> D[Update order.status = cancelled]
    D --> E[Send rejected email]
```

Net stock effect:

```text
reserved_quantity -= qty
on_hand_quantity unchanged
available_quantity increases
```

## Payment Timeout - Stock Released

The recurring job `CancelExpiredOrdersJob` finds:

```text
orders.status = pending_payment
orders.payment_expires_at < now
```

For each expired order:

```mermaid
flowchart TD
    A[CancelExpiredOrdersJob runs] --> B[Find orders where<br/>status = pending_payment<br/>AND payment_expires_at < now]
    B --> C[For each expired order]
    C --> D[Update order.status = cancelled]
    D --> E[Release reserved stock per order item]
    E --> F[Create StockMovement movement_type = released]
    F --> G[Send cancelled email]
```

## Cancellation Before Payment

```mermaid
flowchart TD
    A[Customer requests cancellation] --> B{order.status = pending_payment?}
    B -->|No| C[Cancellation denied]
    B -->|Yes| D{Payment exists?}
    D -->|Yes| E[Cancellation denied]
    D -->|No| F[Cancel order]
    F --> G[Release reserved stock]
```

## Idempotency

Every stock movement has a unique `idempotency_key`. This prevents duplicate reservations, releases, or sales if a request is retried.

Examples:

| Action | Key Pattern |
|--------|-------------|
| Reservation | `idempotency-key-idx` |
| Sold | `sold-payment_id-idx` |
| Rejected | `released-payment_id-idx` |
| Expired | `expired-order_id-idx` |

## Error Handling

| Failure | Action |
|---------|--------|
| Product not found | 404 Not Found |
| Insufficient stock | 409 Conflict |
| Reservation violates constraints | Roll back and return 409 |
| Payment amount less than order total | 422 Unprocessable Entity |
| Payment not in review state | 422 Unprocessable Entity |
| Stock release fails | 422 Unprocessable Entity |
