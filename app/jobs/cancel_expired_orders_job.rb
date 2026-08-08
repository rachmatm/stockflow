class CancelExpiredOrdersJob < ApplicationJob
  def perform
    expired = Order.where(status: :pending_payment)
                   .where("payment_expires_at < ?", Time.current)
                   .includes(:order_items)

    expired.find_each do |order|
      ActiveRecord::Base.transaction do
        order.update!(status: :cancelled, cancelled_at: Time.current)

        order.order_items.each_with_index do |order_item, idx|
          inventory_item = InventoryItem.find_by(
            warehouse_id: order.warehouse_id,
            product_id: order_item.product_id
          )

          next unless inventory_item

          InventoryItem
            .where(id: inventory_item.id)
            .update_counters(reserved_quantity: -order_item.quantity.to_i)

          StockMovement.create!(
            inventory_item:,
            order:,
            movement_type: :released,
            quantity: order_item.quantity,
            idempotency_key: "expired-#{order.id}-#{idx}",
            reference: order.number
          )
        end
      end

      OrderMailer.cancelled_email(order.reload).deliver_later
    end
  end
end
