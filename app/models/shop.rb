class Shop < TenantRecord
  validates :name, presence: true

  has_many :shop_products
  has_many :orders
end
