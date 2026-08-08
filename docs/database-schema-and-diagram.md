# Database Schema and Diagram

## Core Entities

| Table | Purpose |
|-------|---------|
| `customers` | Buyers who can place orders |
| `admins` | Staff who verify or reject payments |
| `products` | Sellable catalog items |
| `warehouses` | Storage locations |
| `inventory_items` | Product stock in a warehouse |
| `orders` | Customer purchase requests |
| `order_items` | Line items inside an order |
| `payments` | Payment proof records for an order |
| `stock_movements` | Audit trail for stock reservation, release, and sale |

## ER Diagram

```text
customers
 1 ---- 1..* orders

products
 1 ---- 1..* order_items
 1 ---- 1..* inventory_items

warehouses
 1 ---- 1..* orders
 1 ---- 1..* inventory_items

orders
 1 ---- 1..* order_items
 1 ---- 0..1 payments
 1 ---- 1..* stock_movements

payments
 1 ---- 0..1 admins (verified_by_id)

stock_movements
 1 ---- 1 inventory_items
 1 ---- 0..1 orders
```

## Rails-style Schema

```ruby
create_table "customers" do |t|
  t.string :email, null: false, unique: true
  t.string :name, null: false
  t.string :login_digest
  t.datetime :login_pin_sent_at
end

create_table "admins" do |t|
  t.string :email, null: false, unique: true
  t.string :name
  t.string :login_digest
  t.datetime :login_pin_sent_at
  t.integer :role, default: 0, null: false
end

create_table "products" do |t|
  t.string :sku, null: false, unique: true
  t.string :name, null: false
  t.integer :price_amount, default: 0, null: false
  t.boolean :active, default: true, null: false
end

create_table "warehouses" do |t|
  t.string :code, null: false, unique: true
  t.string :name, null: false
  t.boolean :active, default: true, null: false
end

create_table "inventory_items" do |t|
  t.bigint :warehouse_id, null: false
  t.bigint :product_id, null: false
  t.integer :on_hand_quantity, default: 0, null: false
  t.integer :reserved_quantity, default: 0, null: false
  t.integer :lock_version, default: 0, null: false

  t.index [:warehouse_id, :product_id], unique: true
  t.check_constraint "on_hand_quantity >= 0"
  t.check_constraint "reserved_quantity >= 0"
  t.check_constraint "reserved_quantity <= on_hand_quantity"
end

create_table "orders" do |t|
  t.string :number, null: false, unique: true
  t.bigint :customer_id, null: false
  t.bigint :warehouse_id
  t.integer :status, default: 0, null: false
  t.integer :subtotal_amount, default: 0, null: false
  t.integer :total_amount, default: 0, null: false
  t.datetime :payment_expires_at, null: false
  t.datetime :paid_at
  t.datetime :cancelled_at
  t.datetime :fulfilled_at
end

create_table "order_items" do |t|
  t.bigint :order_id, null: false
  t.bigint :product_id, null: false
  t.bigint :warehouse_id
  t.string :product_sku, null: false
  t.string :product_name, null: false
  t.integer :quantity, null: false
  t.integer :unit_price_amount, null: false
  t.integer :total_amount, null: false

  t.index [:order_id, :product_id], unique: true
end

create_table "payments" do |t|
  t.bigint :order_id, null: false, unique: true
  t.integer :amount, null: false
  t.integer :status, default: 0, null: false
  t.datetime :submitted_at, null: false
  t.datetime :verified_at
  t.bigint :verified_by_id
  t.string :rejection_reason
end

create_table "stock_movements" do |t|
  t.string :idempotency_key, null: false, unique: true
  t.bigint :inventory_item_id, null: false
  t.bigint :order_id
  t.integer :movement_type, null: false
  t.integer :quantity, null: false
  t.string :reference
end
```

## Key Indexes

| Index | Use |
|-------|-----|
| `orders(customer_id)` | List customer orders |
| `orders(status)` | Admin order workflow |
| `orders(payment_expires_at) where status = 0` | Find expired pending orders |
| `inventory_items(warehouse_id, product_id)` | Unique warehouse-product stock row |
| `payments(order_id)` | One payment per order |
| `stock_movements(idempotency_key)` | Prevent duplicate stock operations |

## Status Enums

### Order

| Value | Status |
|-------|--------|
| 0 | pending_payment |
| 1 | payment_review |
| 2 | paid |
| 3 | cancelled |
| 4 | fulfilled |

### Payment

| Value | Status |
|-------|--------|
| 0 | submitted |
| 1 | verified |
| 2 | rejected |

### Stock Movement

| Value | Type |
|-------|------|
| 0 | reserved |
| 1 | released |
| 2 | sold |
| 3 | adjusted |
