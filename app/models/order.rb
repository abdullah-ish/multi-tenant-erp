class Order < TenantRecord
  belongs_to :shop
  belongs_to :user

  has_many :order_items

  validates :status, presence: true
  validates :total,  numericality: { greater_than_or_equal_to: 0 }

  after_create_commit :enqueue_report_job

  scope :with_report_payload, -> {
    includes(:shop, :user, order_items: { shop_product: :master_product })
  }

  private

  def enqueue_report_job
    OrderReportJob.perform_later(id, Current.company_slug)
  end
end
