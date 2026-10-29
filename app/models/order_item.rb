class OrderItem < TenantRecord
  belongs_to :order
  belongs_to :shop_product

  validates :quantity,   presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
