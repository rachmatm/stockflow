# Multi-User Flow Diagram

## Participants

| Actor | System Name | Example Action |
|-------|-------------|----------------|
| Buyer | Customer | Creates order, uploads payment proof, views invoice |
| Admin | Admin/Ops | Reviews payment, verifies or rejects |
| Scheduler | System Job | Sends reminder, cancels expired unpaid orders |
| Mailpit | Email Sink | Captures notification emails for inspection |

## Main Success Flow

```text
BUYER
  1. Selects products and quantities
  2. Checks stock availability
  3. Places order with selected or automatic warehouse
  4. System reserves stock
  5. System creates pending payment order
  6. System sends invoice email
  7. Buyer uploads payment proof
  8. Order moves to payment_review

ADMIN
  9. Receives admin notification email
 10. Reviews payment proof
 11. Verifies payment
 12. System converts reserved stock to sold stock
 13. Order becomes paid
 14. System sends paid confirmation email
```

## Rejected Payment Flow

```text
BUYER
  1. Uploads payment proof
  2. Order moves to payment_review

ADMIN
  3. Reviews payment proof
  4. Rejects payment with reason

SYSTEM
  5. Sets payment status to rejected
  6. Cancels order
  7. Releases reserved stock
  8. Sends rejected email to buyer
```

## Expired Payment Flow

```text
BUYER
  1. Places order
  2. Does not submit payment before deadline

SCHEDULER
  3. Finds orders where status = pending_payment and payment_expires_at < now
  4. Cancels expired orders
  5. Releases reserved stock
  6. Sends cancelled email to buyer
```

## Early Cancellation Flow

```text
BUYER
  1. Places order
  2. Cancels before uploading payment proof

SYSTEM
  3. Confirms order is still pending_payment
  4. Confirms no payment exists
  5. Cancels order
  6. Releases reserved stock
```

## Sequence Diagram - Happy Path

```text
[Buyer] -> [API]: POST /orders
[API] -> [Inventory]: check available stock
[API] -> [Inventory]: reserve stock
[API] -> [DB]: create order + order_items
[API] -> [Mailpit]: invoice email
[Buyer] -> [API]: submit payment proof
[API] -> [DB]: create payment, order -> payment_review
[API] -> [Mailpit]: admin notify email
[Admin] -> [API]: verify payment
[API] -> [Inventory]: sold movement + reduce on_hand
[API] -> [DB]: order -> paid
[API] -> [Mailpit]: paid confirmation email
```

## Sequence Diagram - Expired Order

```text
[Buyer] -> [API]: POST /orders
[API] -> [Inventory]: reserve stock
[API] -> [DB]: create order status = pending_payment
[Scheduler] -> [DB]: find expired pending orders
[Scheduler] -> [Inventory]: release reserved stock
[Scheduler] -> [DB]: order -> cancelled
[Scheduler] -> [Mailpit]: cancelled email
```

## Sequence Diagram - Rejected Order

```text
[Buyer] -> [API]: submit payment proof
[API] -> [DB]: payment status = submitted
[API] -> [DB]: order -> payment_review
[Admin] -> [API]: reject payment
[API] -> [Inventory]: release reserved stock
[API] -> [DB]: payment -> rejected, order -> cancelled
[API] -> [Mailpit]: rejected email
```

## State Flow

```text
Order States
  pending_payment
    -> payment_review when payment proof submitted
    -> cancelled when buyer cancels early
    -> cancelled when payment expires

  payment_review
    -> paid when admin verifies
    -> cancelled when admin rejects

  paid
    -> fulfilled manually/operationally when fulfillment completes

Stock Effects
  pending_payment:
    reserved_quantity increases

  paid:
    reserved_quantity decreases
    on_hand_quantity decreases

  cancelled:
    reserved_quantity decreases
    on_hand_quantity unchanged
```
