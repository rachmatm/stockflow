class PaymentReminderJob < ApplicationJob
  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order

    OrderMailer.reminder_email(order).deliver_later
  end
end
