class ShopProduct < TenantRecord
  belongs_to :shop
  belongs_to :master_product, optional: true

  validates :name,  presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  has_many :order_items
end
