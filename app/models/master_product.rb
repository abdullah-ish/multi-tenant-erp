class MasterProduct < TenantRecord
  validates :sku,   presence: true, uniqueness: true
  validates :name,  presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  has_many :shop_products
end
