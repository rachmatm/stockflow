class OrderMailer < ApplicationMailer
   default from: "noreply@stockflow-demo.id"

  def invoice_email(order)
    @order = order
    @customer = order.customer
    @items = order.order_items
    @total = order.total_amount
    @expires_at = order.payment_expires_at
    @order_url = "#{frontend_host}/orders/#{@order.number}"
    mail(
      to: @customer.email,
      subject: "Tagihan #{@order.number} - segera lakukan pembayaran"
    )
  end

  def reminder_email(order)
    @order = order
    @customer = order.customer
    @total = order.total_amount
    @expires_at = order.payment_expires_at
    remaining = (@expires_at - Time.current).to_i / 60
    @remaining_minutes = [ remaining, 0 ].max
    @order_url = "#{frontend_host}/orders/#{@order.number}"
    mail(
      to: @customer.email,
      subject: "Segera! Pembayaran #{@order.number} akan kedaluwarsa"
    )
  end

  def paid_email(order)
    @order = order
    @customer = order.customer
    @items = order.order_items
    @total = order.total_amount
    @paid_at = order.paid_at
    @order_url = "#{frontend_host}/orders/#{@order.number}"
    mail(
      to: @customer.email,
      subject: "Pembayaran diterima - #{@order.number}"
    )
  end

  def cancelled_email(order)
    @order = order
    @customer = order.customer
    @reason = order.cancelled_at ? "Batas waktu pembayaran terlewati" : "Pesanan dibatalkan oleh admin"
    @items = order.order_items
    @total = order.total_amount
    @catalog_url = "#{frontend_host}/products"
    mail(
      to: @customer.email,
      subject: "Pesanan #{@order.number} dibatalkan"
    )
  end

  def rejected_email(order)
    @order = order
    @customer = order.customer
    @payment = order.payment
    @reason = @payment&.rejection_reason || "Rejected by admin"
    @total = order.total_amount
    @expires_at = order.payment_expires_at
    @order_url = "#{frontend_host}/orders/#{@order.number}"
    mail(
      to: @customer.email,
      subject: "Bukti pembayaran #{@order.number} perlu diperbaiki"
    )
  end

  def admin_notify_email(order)
    @order = order
    @customer = order.customer
    @items = order.order_items
    @total = order.total_amount
    @admin_url = "#{frontend_host}/admin/payments"
    mail(
       to: "ops@stockflow-demo.id",
      subject: "[Internal] Bukti bayar baru - #{@order.number} perlu verifikasi"
    )
  end

  private

  def frontend_host
    ENV.fetch("FRONTEND_HOST", default_frontend_host)
  end

  def default_frontend_host
    if Rails.env.production?
      "https://app.rachmat.pro"
    elsif Rails.env.staging?
      "http://staging.rachmat.pro"
    else
      "http://localhost:5173"
    end
  end
end
