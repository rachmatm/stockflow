# StockFlow Demo - Order & Inventory Management

Demo application showcasing the order lifecycle with stock reservation, payment SLA, automatic stock release, and invoice fulfillment.

## Live Staging

| Service | URL |
|---------|-----|
| Frontend | https://demo.rachmat.pro |
| API | https://api.demo.rachmat.pro |
| API Docs (Rswag) | https://api.demo.rachmat.pro/api-docs |
| Mailpit (Email Inspector) | http://100.66.185.79:8025 |
| Solid Queue Dashboard | https://api.demo.rachmat.pro/mission_control/jobs |

## Order Lifecycle

```
Order Placement -> Pending Payment -> Paid -> Fulfilled
                              |
                              +-> Timeout -> Cancelled (stock auto-released)
                              +-> Rejected (admin) -> Rejected (stock auto-released)
```

### Step-by-step flow

1. **Order Placement** -- Buyer selects products and quantity. System checks warehouse stock availability before creating the order.

2. **Stock Reservation & Billing** -- Available stock is locked (reserved) so other buyers cannot claim it. Invoice is generated with payment SLA (deadline).

3. **Payment Verification** -- Buyer uploads proof of payment via available channels. Admin verifies via dashboard. On confirmation, order becomes `Paid` and reserved stock is permanently deducted.

4. **Automatic Stock Release** -- If payment deadline passes without confirmation, status becomes `Cancelled` and reserved stock is automatically returned to the warehouse.

5. **Fulfillment & Notifications** -- Digital invoice/receipt is emailed to the buyer automatically.

## Outgoing Emails

All emails are routed through **Mailpit** (local SMTP sink) instead of real SMTP. This means:

- No emails are sent to real recipients during development/staging
- All outgoing emails are captured and viewable in the Mailpit web UI at `http://100.66.185.79:8025`
- You can inspect raw headers, HTML source, and body of every email
- Mailpit provides an API at `/api/v1/messages` for programmatic inspection

### Email types sent by the system

| Trigger | Email | Recipient |
|---------|-------|-----------|
| Order created | Invoice | Buyer |
| Payment due (1 day before SLA) | Payment Reminder | Buyer |
| Payment confirmed | Paid Confirmation | Buyer |
| Payment expired | Cancelled Notification | Buyer |
| Payment rejected (admin) | Rejected Notification | Buyer |
| Admin verifies/rejects payment | Admin Notification | ops@stockflow-demo.id |
| User registers | Welcome + Login PIN | New user |
| User forgets PIN | Login PIN resend | Existing user |

### Mailpit usage

```bash
# View all emails in terminal
mailpit --list

# Inspect latest email
mailpit --latest

# Access via browser
open http://100.66.185.79:8025

# Mailpit API
curl http://100.66.185.79:8025/api/v1/messages | jq '.[0] | {from, to, subject}'

# Delete all messages
curl -X DELETE http://100.66.185.79:8025/api/v1/messages
```

### SMTP configuration

```yaml
# config/environments/development.rb (or staging)
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: "100.66.185.79",
  port: 1025,          # Mailpit listens on 1025
  user_name: "",
  password: "",
  authentication: :none
}
config.action_mailer.default_url_options = { host: "demo.rachmat.pro", port: 443 }
```

## Project Structure (copied files)

```
app/
  controllers/
    v1/
      orders_controller.rb           # Order placement, payment status checks
      admin/
        payments_controller.rb       # Payment verification, rejection
        stock_movements_controller.rb
  jobs/
    cancel_expired_orders_job.rb     # SLA expiry -> cancel + release stock
    payment_reminder_job.rb          # 1-day-before deadline reminder
  mailers/
    application_mailer.rb
    order_mailer.rb                  # 6 order lifecycle emails
    auth_mailer.rb                   # Welcome + Login PIN
  models/
    order.rb
    order_item.rb
    payment.rb
    stock_movement.rb
  views/
    layouts/
      mailer.html.erb
      mailer.text.erb
    order_mailer/
      invoice_email.html.erb
      reminder_email.html.erb
      paid_email.html.erb
      cancelled_email.html.erb
      rejected_email.html.erb
      admin_notify_email.html.erb
    auth_mailer/
      welcome_email.html.erb
      login_pin_email.html.erb
```

## Environment Variables

| Variable | Value (staging) |
|----------|-----------------|
| SMTP_ADDRESS | 100.66.185.79 |
| SMTP_PORT | 1025 (Mailpit) |
| SMTP_AUTH | none |
| SMTP_DOMAIN | demo.rachmat.pro |

## Related

- Full source: https://github.com/rachmatm/tata-niaga
- Staging deployment: `bin/kamal deploy --destination staging`
