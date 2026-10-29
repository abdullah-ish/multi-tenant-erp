class ProductSyncJob < ApplicationJob
  queue_as :default

  def perform(company_slug, csv_path = nil)
    csv_path ||= Rails.root.join("db/csv/#{company_slug}_products.csv").to_s

    unless File.exist?(csv_path)
      Rails.logger.warn "[ProductSyncJob] CSV file not found: #{csv_path}"
      return
    end

    TenantConnection.switch(company_slug) do
      rows = []
      now  = Time.current

      CSV.foreach(csv_path, headers: true) do |row|
        rows << {
          sku:        row["sku"],
          name:       row["name"],
          price:      row["price"].to_d,
          synced_at:  now,
          created_at: now,
          updated_at: now
        }
      end

      MasterProduct.upsert_all(
        rows,
        unique_by: :sku,
        update_only: [:name, :price, :synced_at]
      )

      Rails.logger.info "[ProductSyncJob] Synced #{rows.size} products for #{company_slug}"
    end
  end
end
