class StockMovement < ApplicationRecord
  belongs_to :inventory_item
  belongs_to :order, optional: true

  enum :movement_type, {
    reserved: 0,
    released: 1,
    sold: 2,
    adjusted: 3
  }

  validates :idempotency_key, presence: true, uniqueness: true
  validates :quantity,
            numericality: { only_integer: true, greater_than: 0 }
end
