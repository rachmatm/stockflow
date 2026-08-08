# frozen_string_literal: true

class V1::Admin::StockMovementsController < V1::Admin::BaseController
  def index
    movements = StockMovement
      .where(movement_type: %w[sold released])
      .includes(inventory_item: [ :product, :warehouse ], order: [ :customer ])
      .order(created_at: :desc)

    if params[:movement_type]
      movements = movements.where(movement_type: params[:movement_type])
    end

    result = paginated(movements, params)

    render json: {
      data: result[:data].map { |m| serialize_movement(m) },
      meta: {
        page: result[:page],
        per: result[:per],
        total: result[:total],
        total_pages: result[:total_pages]
      }
    }
  end

  private

  def serialize_movement(m)
    item = m.inventory_item
    product = item&.product
    warehouse = item&.warehouse

    {
      id: m.id,
      movement_type: m.movement_type,
      quantity: m.quantity,
      reference: m.reference,
      idempotency_key: m.idempotency_key,
      product_sku: product&.sku,
      product_name: product&.name,
      warehouse_code: warehouse&.code,
      warehouse_name: warehouse&.name,
      order_number: m.order&.number,
      customer_name: m.order&.customer&.name,
      created_at: m.created_at&.iso8601
    }
  end
end
