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

```text
1. Find selected or auto-chosen warehouse for each product
2. Confirm inventory_items.warehouse_id + product_id
3. Check available_quantity >= requested_quantity
4. Increment reserved_quantity atomically
5. Refresh the row and re-check reserved_quantity <= on_hand_quantity
6. Create StockMovement(movement_type = reserved)
7. Create Order and OrderItem in the same transaction
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

```text
Search active warehouses for the requested product.
Select the inventory row with the highest available_quantity.
Proceed only if available_quantity >= requested_quantity.
```

## Payment Verification - Stock Sold

When admin verifies payment:

```text
For each order item:
  1. Decrement reserved_quantity by item quantity
  2. Decrement on_hand_quantity by item quantity
  3. Create StockMovement(movement_type = sold)
  4. Update order.status = paid
  5. Send paid confirmation email
```

Net stock effect:

```text
reserved_quantity -= qty
on_hand_quantity -= qty
available_quantity stays consistent because both sides decrease by qty
```

## Rejection - Stock Released

When admin rejects payment:

```text
For each order item:
  1. Decrement reserved_quantity by item quantity
  2. Create StockMovement(movement_type = released)
  3. Update order.status = cancelled
  4. Send rejected email
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

```text
1. Update order.status = cancelled
2. Release reserved stock per order item
3. Create StockMovement(movement_type = released)
4. Send cancelled email
```

## Cancellation Before Payment

A customer can cancel only while:

```text
order.status = pending_payment
payment does not exist
```

The system cancels the order and releases reserved stock.

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
