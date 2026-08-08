# frozen_string_literal: true

class V1::Admin::PaymentsController < V1::Admin::BaseController
  before_action :set_payment, only: %i[verify reject]

  def pending_count
    count = Order.where(status: :payment_review).count
    render json: { count: count }
  end

  def verify
    order = payment.order

    unless order.status == "payment_review"
      render_error(status: :unprocessable_entity, errors: [ "Payment not in review state" ])
      return
    end

    ActiveRecord::Base.transaction do
      payment.update!(status: :verified, verified_at: Time.current, verified_by_id: current_user_id)
      order.update!(status: :paid, paid_at: Time.current)

      order.order_items.each_with_index do |order_item, idx|
        inventory_item = InventoryItem.find_by(warehouse_id: order.warehouse_id, product_id: order_item.product_id)

        InventoryItem
          .where(id: inventory_item.id)
          .update_counters(reserved_quantity: -order_item.quantity, on_hand_quantity: -order_item.quantity)

        StockMovement.create!(
          inventory_item:,
          order:,
          movement_type: :sold,
          quantity: order_item.quantity,
          idempotency_key: "sold-#{payment.id}-#{idx}",
          reference: order.number
        )
      end
    end

    OrderMailer.paid_email(order).deliver_later
    render_resource(payment.reload)
  rescue ActiveRecord::RecordInvalid => e
    render_error(status: :unprocessable_entity, errors: e.message.split("."))
  end

  def reject
    order = payment.order

    unless order.status == "payment_review"
      render_error(status: :unprocessable_entity, errors: [ "Payment not in review state" ])
      return
    end

    reason = params[:rejection_reason] || "Rejected by admin"

    ActiveRecord::Base.transaction do
      payment.update!(status: :rejected, rejection_reason: reason, verified_by_id: current_user_id)
      order.update!(status: :cancelled, cancelled_at: Time.current)

      order.order_items.each_with_index do |order_item, idx|
        inventory_item = InventoryItem.find_by(warehouse_id: order.warehouse_id, product_id: order_item.product_id)

        release_amount = -order_item.quantity.to_i

        InventoryItem
          .where(id: inventory_item.id)
          .update_counters(reserved_quantity: release_amount)

        refreshed = InventoryItem.find(inventory_item.id)
        if refreshed.reserved_quantity < 0
          InventoryItem
            .where(id: inventory_item.id)
            .update_counters(reserved_quantity: -release_amount)
          raise StockReleaseError, "Failed to release stock for #{order_item.product_sku}"
        end

        StockMovement.create!(
          inventory_item:,
          order:,
          movement_type: :released,
          quantity: order_item.quantity,
          idempotency_key: "released-#{payment.id}-#{idx}",
          reference: order.number
        )
      end
    end

    OrderMailer.rejected_email(order).deliver_later
    render_resource(payment.reload)
  rescue StockReleaseError => e
    render_error(status: :unprocessable_entity, errors: [ e.message ])
  rescue ActiveRecord::RecordInvalid => e
    render_error(status: :unprocessable_entity, errors: e.message.split("."))
  end

  class StockReleaseError < StandardError; end

  private

  def set_payment
    @payment = Payment.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(status: :not_found, errors: [ "Payment not found" ])
  end

  def payment
    @payment
  end
end
