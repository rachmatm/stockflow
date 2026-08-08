# Multi-User Flow Diagram

## Participants

| Actor | System Name | Example Action |
|-------|-------------|----------------|
| Buyer | Customer | Creates order, uploads payment proof, views invoice |
| Admin | Admin/Ops | Reviews payment, verifies or rejects |
| Scheduler | System Job | Sends reminder, cancels expired unpaid orders |
| Mailpit | Email Sink | Captures notification emails for inspection |

## Main Success Flow

```mermaid
sequenceDiagram
    participant Buyer
    participant API
    participant Inventory
    participant DB
    participant Admin
    participant Mailer

    Buyer->>API: Selects products and quantities
    API->>Inventory: Checks stock availability
    Buyer->>API: Places order (auto/selected warehouse)
    API->>Inventory: Reserves stock
    API->>DB: Creates pending payment order
    API->>Mailer: Sends invoice email
    Buyer->>API: Uploads payment proof
    API->>DB: Order moves to payment_review
```

## Rejected Payment Flow

```mermaid
sequenceDiagram
    participant Buyer
    participant API
    participant Admin
    participant Inventory
    participant DB
    participant Mailer

    Buyer->>API: Uploads payment proof
    API->>DB: Order moves to payment_review
    Admin->>API: Reviews and rejects payment (with reason)
    API->>DB: Payment status = rejected
    API->>DB: Order = cancelled
    API->>Inventory: Releases reserved stock
    API->>Mailer: Sends rejected email to buyer
```

## Expired Payment Flow

```mermaid
sequenceDiagram
    participant Buyer
    participant API
    participant Scheduler
    participant Inventory
    participant DB
    participant Mailer

    Buyer->>API: Places order
    API->>DB: Order created (pending_payment)
    Note over Scheduler,DB: Payment deadline passes
    Scheduler->>DB: Finds expired pending orders
    Scheduler->>DB: Order = cancelled
    Scheduler->>Inventory: Releases reserved stock
    Scheduler->>Mailer: Sends cancelled email to buyer
```

## Early Cancellation Flow

```mermaid
sequenceDiagram
    participant Buyer
    participant API
    participant Inventory
    participant DB

    Buyer->>API: Places order
    Buyer->>API: Cancels before uploading payment proof
    API->>DB: Confirms status = pending_payment
    API->>DB: Confirms no payment exists
    API->>DB: Order = cancelled
    API->>Inventory: Releases reserved stock
```

## Sequence Diagram - Happy Path

```mermaid
sequenceDiagram
    participant Buyer
    participant API
    participant Inventory
    participant DB
    participant Admin
    participant Mailer

    Buyer->>API: POST /orders
    API->>Inventory: Check available stock
    API->>Inventory: Reserve stock
    API->>DB: Create order + order_items
    API->>Mailer: Invoice email
    Buyer->>API: Submit payment proof
    API->>DB: Create payment, order -> payment_review
    API->>Mailer: Admin notify email
    Admin->>API: Verify payment
    API->>Inventory: Sold movement + reduce on_hand
    API->>DB: Order -> paid
    API->>Mailer: Paid confirmation email
```

## Sequence Diagram - Expired Order

```mermaid
sequenceDiagram
    participant Buyer
    participant API
    participant Inventory
    participant DB
    participant Scheduler
    participant Mailer

    Buyer->>API: POST /orders
    API->>Inventory: Reserve stock
    API->>DB: Create order (status = pending_payment)
    Note over Scheduler,DB: Payment expires
    Scheduler->>DB: Find expired pending orders
    Scheduler->>Inventory: Release reserved stock
    Scheduler->>DB: Order -> cancelled
    Scheduler->>Mailer: Cancelled email
```

## Sequence Diagram - Rejected Order

```mermaid
sequenceDiagram
    participant Buyer
    participant API
    participant Inventory
    participant DB
    participant Admin
    participant Mailer

    Buyer->>API: Submit payment proof
    API->>DB: Payment status = submitted
    API->>DB: Order -> payment_review
    Admin->>API: Reject payment
    API->>Inventory: Release reserved stock
    API->>DB: Payment -> rejected, Order -> cancelled
    API->>Mailer: Rejected email
```

## State Flow

```mermaid
stateDiagram-v2
    [*] --> pending_payment
    pending_payment --> payment_review: Payment proof submitted
    pending_payment --> cancelled: Buyer cancels early
    pending_payment --> cancelled: Payment expires
    payment_review --> paid: Admin verifies
    payment_review --> cancelled: Admin rejects
    paid --> fulfilled: Fulfillment completes

    note right of pending_payment
        Stock Effect:
        reserved_quantity increases
    end note

    note right of paid
        Stock Effect:
        reserved_quantity decreases
        on_hand_quantity decreases
    end note

    note right of cancelled
        Stock Effect:
        reserved_quantity decreases
        on_hand_quantity unchanged
    end note
```
