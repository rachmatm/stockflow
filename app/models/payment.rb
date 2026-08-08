class Payment < ApplicationRecord
  belongs_to :order

  has_one_attached :proof_image

  enum :status, {
    submitted: 0,
    verified: 1,
    rejected: 2
  }

  validates :amount,
            numericality: { only_integer: true, greater_than: 0 }
end
