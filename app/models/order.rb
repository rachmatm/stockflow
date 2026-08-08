class Order < ApplicationRecord
  belongs_to :customer
  belongs_to :warehouse, optional: true

  has_many :order_items, dependent: :restrict_with_error
  has_one :payment, dependent: :restrict_with_error
  has_many :stock_movements, dependent: :restrict_with_error

  before_validation :generate_number, on: :create

  enum :status, {
    pending_payment: 0,
    payment_review: 1,
    paid: 2,
    cancelled: 3,
    fulfilled: 4
  }

  validates :number, presence: true, uniqueness: true
  validates :payment_expires_at, presence: true

  def generate_number
    self.number ||= "TIB-#{Time.current.strftime('%Y%m%d')}-#{'%06d' % SecureRandom.random_number(10**6)}"
  end
end
