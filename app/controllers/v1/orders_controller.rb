# frozen_string_literal: true

class V1::OrdersController < V1::BaseController
  before_action :set_order, only: %i[show]
  before_action :set_order_by_number, only: %i[show_by_number submit_payment invoice cancel]
  before_action :authorize_customer_order!, only: %i[show show_by_number submit_payment invoice cancel]

  def index
    scope = Order.includes(:order_items, :payment).order(created_at: :desc)
    if current_user_role != "admin"
      scope = scope.where(customer_id: current_user_id)
    end
    result = paginated(scope, params)
    render json: {
      data: result[:data].map { |o| serialize_order(o) },
      meta: {
        page: result[:page],
        per: result[:per],
        total: result[:total],
        total_pages: result[:total_pages]
      }
    }
  end

  def show
    order = Order.includes(:order_items, :payment).find(params[:id])
    data = serialize_order(order)
    render_resource(data)
  end

  def show_by_number
    order = Order.includes(:order_items, :payment).find(@order.id)
    render_resource(serialize_order(order))
  end

  def create
    if current_user_role != "admin" && params[:customer_id].to_i != current_user_id
      render_error(status: :forbidden, errors: [ "Customer access denied" ])
      return
    end

    customer = Customer.find(params[:customer_id])
    items_params = Array(params[:items])
    warehouse_selection = (params[:warehouse_selection] || "selected").to_s
    idempotency_key = request.headers["Idempotency-Key"]

    if idempotency_key
      existing_movement = StockMovement.find_by(idempotency_key: "#{idempotency_key}-0")
      if existing_movement&.order
        data = serialize_order(existing_movement.order)
        return render_resource(data)
      end
    end

    warehouse = nil
    if warehouse_selection == "selected"
      warehouse = Warehouse.find(params[:warehouse_id])
    end

    reserved = reserve_stock(warehouse_selection:, warehouse:, items_params:)

    if reserved[:errors]
      render_error(status: :conflict, errors: reserved[:errors])
      return
    end

    order = nil

    ActiveRecord::Base.transaction do
      order = Order.new(
        customer:,
        warehouse:,
        status: :pending_payment,
        payment_expires_at: 30.minutes.from_now,
        subtotal_amount: reserved[:total],
        total_amount: reserved[:total]
      )
      order.save!

      items_data = reserved[:items]

      items_data.each_with_index do |item_data, idx|
        order.order_items.create!(
          product: item_data[:product],
          product_sku: item_data[:product_sku],
          product_name: item_data[:product_name],
          quantity: item_data[:quantity],
          unit_price_amount: item_data[:unit_price_amount],
          total_amount: item_data[:total_amount],
          warehouse_id: item_data[:warehouse_id]
        )

        StockMovement.create!(
          inventory_item_id: item_data[:inventory_item_id],
          order:,
          movement_type: :reserved,
          quantity: item_data[:quantity],
          idempotency_key: "#{idempotency_key || SecureRandom.uuid}-#{idx}",
          reference: order.number
        )
      end
    end

    data = serialize_order(order.reload)
    OrderMailer.invoice_email(order).deliver_later
    PaymentReminderJob
      .set(wait_until: order.payment_expires_at - 5.minutes)
      .perform_later(order.id)
    render_resource(data, status: :created)
  rescue ActiveRecord::RecordNotFound => e
    render_error(status: :not_found, errors: [ e.message ])
  rescue InsufficientStockError => e
    msg = if warehouse
      e.message.sub(/Insufficient stock for product (.+)$/, "\\1 tidak tersedia di gudang #{warehouse.name}")
    else
      e.message
    end
    render_error(status: :conflict, errors: [ msg ])
  rescue ActiveRecord::RecordInvalid => e
    render_error(status: :unprocessable_entity, errors: e.message.split("."))
  rescue ActiveRecord::StatementInvalid, ActiveRecord::TransactionRollbackError
    release_stock!
    render_error(status: :conflict, errors: [ "Insufficient stock for one or more products di gudang #{warehouse&.name || "yang dipilih"}" ])
  end

  def check_availability
    items_params = Array(params[:items])
    warehouse_selection = (params[:warehouse_selection] || "selected").to_s
    selected_wh_id = params[:warehouse_id]&.to_i
    active_wh = Warehouse.where(active: true)

    result = { available: false, mode: warehouse_selection, items: [], missing: [], suggestions: [] }

    items_params.each do |item_params|
      product = Product.find(item_params[:product_id])
      quantity = item_params[:quantity].to_i
      per_wh = {}

      active_wh.find_each do |wh|
        ii = InventoryItem.find_by(warehouse_id: wh.id, product_id: product.id)
        avail = ii&.available_quantity || 0
        per_wh[wh.id] = { name: wh.name, code: wh.code, available: avail }
      end

      item_result = {
        product_id: product.id,
        product_sku: product.sku,
        product_name: product.name,
        requested: quantity,
        per_warehouse: per_wh
      }

      if per_wh.empty? || per_wh.values.all? { |v| v[:available] < quantity }
        result[:missing] << item_result
        result[:items] << item_result
        next
      end

      if warehouse_selection == "selected" && selected_wh_id
        wh_data = per_wh[selected_wh_id]
        if wh_data && wh_data[:available] >= quantity
          item_result[:selected_warehouse_id] = selected_wh_id
          item_result[:selected_warehouse_name] = wh_data[:name]
          item_result[:available] = wh_data[:available]
        else
          result[:missing] << item_result
        end
        result[:items] << item_result
        next
      end

      if warehouse_selection == "auto"
        best = per_wh.max_by { |_, v| v[:available] }
        if best && best[1][:available] >= quantity
          item_result[:selected_warehouse_id] = best[0]
          item_result[:selected_warehouse_name] = best[1][:name]
          item_result[:available] = best[1][:available]
          result[:items] << item_result
        else
          result[:missing] << item_result
        end
        next
      end

      result[:items] << item_result
    end

    result[:available] = result[:missing].empty?
    if result[:available]
      result[:suggestions] = Array.wrap(result[:items].map { |i| i[:selected_warehouse_name] }.uniq)
    end

    render_resource(result)
  rescue ActiveRecord::RecordNotFound => e
    render_error(status: :not_found, errors: [ e.message ])
  end

  def cancel
    unless @order.status == "pending_payment" && @order.payment.nil?
      render_error(status: :unprocessable_entity, errors: [ "Order can only be cancelled before payment proof is uploaded" ])
      return
    end

    @order.update!(status: :cancelled, cancelled_at: Time.current)
    release_order_stock!
    render_resource(serialize_order(@order.reload))
  end

  def submit_payment
    if @order.status != "pending_payment"
      render_error(status: :unprocessable_entity, errors: [ "Order is not pending payment" ])
      return
    end

    proof_image = params[:payment][:proof_image]
    amount = params[:payment][:amount].to_i

    if amount < @order.total_amount
      render_error(status: :unprocessable_entity, errors: [ "Payment amount is less than order total" ])
      return
    end
    payment = nil

    ActiveRecord::Base.transaction do
      payment = Payment.new(
        order: @order,
        amount:,
        status: :submitted,
        submitted_at: Time.current
      )

      if proof_image.present?
        payment.proof_image.attach(proof_image)
      end

      payment.save!
      @order.update!(status: :payment_review)
    end

    OrderMailer.admin_notify_email(@order).deliver_later
    render_resource(payment.reload, status: :created)
  rescue ActiveRecord::RecordInvalid => e
    render_error(status: :unprocessable_entity, errors: e.message.split("."))
  end

  def invoice
    order = Order.includes(:order_items, :customer, :warehouse, :payment).find(@order.id)
    render html: invoice_html(order)
  end

  class InsufficientStockError < StandardError; end

  private

  def set_order
    @order = Order.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error(status: :not_found, errors: [ "Order not found" ])
  end

  def set_order_by_number
    @order = if params[:number].match?(/\A\d+\z/)
      Order.find_by(id: params[:number])
    else
      Order.find_by(number: params[:number])
    end
    render_error(status: :not_found, errors: [ "Order not found" ]) unless @order
  end

  def authorize_customer_order!
    return if current_user_role == "admin"
    return if @order&.customer_id == current_user_id
    render_error(status: :not_found, errors: [ "Order not found" ])
  end

  def reserve_stock(warehouse_selection:, warehouse: nil, items_params:)
    total = 0
    items_data = []
    active_wh = Warehouse.where(active: true)

    items_params.each do |item_params|
      product = Product.find(item_params[:product_id])
      quantity = item_params[:quantity].to_i
      selected_wh = nil
      inventory_item = nil

      if warehouse_selection == "selected" && warehouse
        inventory_item = InventoryItem.find_by(warehouse_id: warehouse.id, product_id: product.id)
        selected_wh = warehouse
      elsif warehouse_selection == "auto"
        candidates = InventoryItem
          .where(product_id: product.id)
          .joins("INNER JOIN warehouses w ON inventory_items.warehouse_id = w.id")
          .where(warehouses: { active: true })
          .where("on_hand_quantity - reserved_quantity >= ?", quantity)
          .order(Arel.sql("(on_hand_quantity - reserved_quantity) DESC"))
        inventory_item = candidates.first
        selected_wh = Warehouse.find(inventory_item.warehouse_id) if inventory_item
      end

      unless inventory_item && inventory_item.available_quantity >= quantity
        raise InsufficientStockError, "Insufficient stock for product #{product.sku}"
      end

      InventoryItem
        .where(id: inventory_item.id)
        .update_counters(reserved_quantity: quantity)

      refreshed = InventoryItem.find(inventory_item.id)
      unless refreshed.reserved_quantity <= refreshed.on_hand_quantity
        InventoryItem
          .where(id: inventory_item.id)
          .update_counters(reserved_quantity: -quantity)
        raise InsufficientStockError, "Insufficient stock for product #{product.sku}"
      end

      unit_price = product.price_amount
      item_total = unit_price * quantity
      total += item_total

      items_data << {
        product:,
        product_sku: product.sku,
        product_name: product.name,
        quantity:,
        unit_price_amount: unit_price,
        total_amount: item_total,
        inventory_item_id: inventory_item.id,
        warehouse_id: selected_wh&.id
      }
    end

    { total:, items: items_data }
  end

  def release_stock!
    # Best-effort release of any pending stock movements without a paid order
    StockMovement
      .joins(:order)
      .where("stock_movements.movement_type = ? AND orders.status != ?", StockMovement.movement_types[:reserved], "paid")
      .find_each do |movement|
        inventory_item = InventoryItem.find(movement.inventory_item_id)
        InventoryItem
          .where(id: inventory_item.id)
          .update_counters(reserved_quantity: -movement.quantity)
        movement.destroy
      end
  end

  def release_order_stock!
    StockMovement
      .where(order: @order, movement_type: StockMovement.movement_types[:reserved])
      .find_each do |movement|
        InventoryItem
          .where(id: movement.inventory_item_id)
          .update_counters(reserved_quantity: -movement.quantity)
        movement.destroy
      end
  end

  def serialize_order(order)
    {
      id: order.id,
      number: order.number,
      status: order.status,
      customer_id: order.customer_id,
      warehouse_id: order.warehouse_id,
      subtotal_amount: order.subtotal_amount,
      total_amount: order.total_amount,
      payment_expires_at: order.payment_expires_at&.iso8601,
      paid_at: order.paid_at&.iso8601,
      cancelled_at: order.cancelled_at&.iso8601,
      fulfilled_at: order.fulfilled_at&.iso8601,
      created_at: order.created_at&.iso8601,
      updated_at: order.updated_at&.iso8601,
      order_items: order.order_items.map { |oi|
        {
          id: oi.id,
          product_id: oi.product_id,
          product_sku: oi.product_sku,
          product_name: oi.product_name,
          quantity: oi.quantity,
          unit_price_amount: oi.unit_price_amount,
          total_amount: oi.total_amount,
          warehouse_id: oi.warehouse_id
        }
      },
      payment: order.payment ? {
        id: order.payment.id,
        status: order.payment.status,
        amount: order.payment.amount,
        submitted_at: order.payment.submitted_at&.iso8601,
        verified_at: order.payment.verified_at&.iso8601,
        rejection_reason: order.payment.rejection_reason,
        proof_image_url: order.payment.proof_image.attached? ? "#{request.base_url}#{Rails.application.routes.url_helpers.rails_blob_path(order.payment.proof_image, only_path: true)}" : nil
      } : nil
    }
  end

  def invoice_html(order)
    esc = ->(v) { ERB::Util.html_escape(v.to_s) }

    line_items_html = order.order_items.map { |oi|
      %(<tr><td>#{esc.call(oi.product_name)}</td><td class="num">#{esc.call(oi.product_sku)}</td><td class="num">#{esc.call(oi.quantity)}</td><td class="num">#{esc.call(oi.unit_price_amount)}</td><td class="num">#{esc.call(oi.total_amount)}</td></tr>)
    }.join.html_safe

    customer = order.customer
    warehouse = order.warehouse
    payment = order.payment

    %(
      <html><head><meta charset="utf-8"><title>Invoice #{esc.call(order.number)}</title>
      <style>
        body{font-family:Arial,sans-serif;margin:40px;color:#333}
        h1{margin-bottom:0}
        .meta{color:#666;margin-bottom:20px}
        table{width:100%;border-collapse:collapse;margin:20px 0}
        th,td{padding:8px 12px;border:1px solid #ddd;text-align:left}
        th{background:#f5f5f5}
        .num{text-align:right}
        .total{font-weight:bold}
        .status{margin-top:20px;padding:10px;border-radius:4px}
        .paid{background:#d4edda;color:#155724}
        .pending{background:#fff3cd;color:#856404}
      </style></head><body>
      <h1>Invoice #{esc.call(order.number)}</h1>
      <p class="meta">Date: #{esc.call(order.created_at&.strftime('%B %d, %Y %H:%M'))}</p>
      <table>
        <tr><th>Customer</th><td>#{esc.call(customer&.name)}</td></tr>
        <tr><th>Email</th><td>#{esc.call(customer&.email)}</td></tr>
        <tr><th>Warehouse</th><td>#{esc.call(warehouse&.name)} (#{esc.call(warehouse&.code)})</td></tr>
      </table>
      <table>
        <thead><tr><th>Item</th><th>SKU</th><th>Qty</th><th>Unit Price</th><th>Total</th></tr></thead>
        <tbody>#{line_items_html}</tbody>
        <tfoot><tr class="total"><td colspan="4">Subtotal</td><td class="num">#{esc.call(order.subtotal_amount)}</td></tr>
        <tr class="total"><td colspan="4">Total</td><td class="num">#{esc.call(order.total_amount)}</td></tr></tfoot>
      </table>
      <div class="status #{order.status == 'paid' ? 'paid' : 'pending'}">Status: #{esc.call(order.status.humanize)}</div>
      <p>Payment: #{payment ? "Amount #{esc.call(payment.amount)} (#{esc.call(payment.status)})" : "Not yet submitted"}</p>
      </body></html>
    ).html_safe
  end
end
