# High-Level Design

## Scope

StockFlow Demo models an order and inventory system where buyers can place orders, reserve stock, submit payment proof, and receive fulfillment notifications. Admins verify or reject payments, while the system automatically cancels expired unpaid orders and releases reserved stock.

## System Goals

1. Prevent overselling by reserving stock at order creation time.
2. Enforce a payment service level agreement.
3. Automatically release stock when payment expires or is rejected.
4. Deduct inventory only after payment verification.
5. Audit every stock movement.
6. Notify buyers and admins through email.

## Primary Users

| Role | Responsibility |
|------|----------------|
| Customer / Buyer | Browse products, check availability, create order, upload payment proof, view order status |
| Admin / Ops | Verify or reject payment, review stock movement, monitor operations |
| System / Scheduler | Send payment reminders, cancel expired orders, release reserved stock |
| Mailpit | Capture staging emails for inspection instead of sending real outbound mail |

## High-Level Components

```mermaid
flowchart TD
    subgraph Customer["Customer"]
        C1["Product Catalog / Availability API"]
        C2["Order Placement API"]
        C3["Payment Proof Upload API"]
        C4["Invoice / Order Status View"]
    end

    subgraph Backend["Backend Rails API"]
        B1[Auth Controller]
        B2[Orders Controller]
        B3[Admin Payments Controller]
        B4[StockMovement Controller]
        B5[Order Mailer]
        B6[Auth Mailer]
        B7[Solid Queue Jobs]
    end

    subgraph Databases["Databases"]
        DB1["Primary DB<br/>users, products, warehouses,<br/>orders, inventory, payments"]
        DB2["Queue DB<br/>job scheduler and recurring tasks"]
    end

    subgraph External["External / Local Services"]
        E1["Mailpit SMTP sink"]
        E2["Docker Registry"]
        E3["Kamal deploy/proxy"]
    end
```

## Application Flow

```mermaid
flowchart TD
    A[Customer chooses product] --> B[System checks available quantity]
    B --> C[System reserves stock]
    C --> D[System creates order with payment deadline]
    D --> E[Invoice email is enqueued]
    E --> F[Reminder job is scheduled]
    F --> G[Customer uploads payment proof]
    G --> H{Admin Action}
    H -->|Verifies| I[Stock becomes sold<br/>on-hand decreases]
    H -->|Rejects| J[Reservation is released]
    K[Expired: scheduled job] --> L[Cancels and releases reservation]
```

## Deployment

Staging is deployed with:

```bash
bin/kamal deploy --destination staging
```

Runtime services:

| Service | Endpoint |
|---------|----------|
| API | https://api.demo.rachmat.pro |
| Frontend | https://demo.rachmat.pro |
| Mailpit | http://100.66.185.79:8025 |
| Queue UI | https://api.demo.rachmat.pro/mission_control/jobs |
