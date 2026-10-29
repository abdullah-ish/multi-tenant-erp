require "rails_helper"

RSpec.describe ProductSyncJob, type: :job do
  let(:company_slug) { "acme" }
  let(:csv_path)     { Rails.root.join("spec/fixtures/acme_test_products.csv").to_s }

  before do
    FileUtils.mkdir_p(Rails.root.join("spec/fixtures"))
    File.write(csv_path, <<~CSV)
      sku,name,price
      TEST-001,Test Widget One,5.00
      TEST-002,Test Widget Two,10.00
      TEST-003,Test Widget Three,15.00
    CSV
  end

  after { File.delete(csv_path) if File.exist?(csv_path) }

  it "creates 3 products from the fixture CSV" do
    TenantConnection.switch(company_slug) do
      before_count = MasterProduct.where(sku: %w[TEST-001 TEST-002 TEST-003]).count
    end

    ProductSyncJob.perform_now(company_slug, csv_path)

    TenantConnection.switch(company_slug) do
      after_count = MasterProduct.where(sku: %w[TEST-001 TEST-002 TEST-003]).count
      expect(after_count).to eq(3)
    end
  end

  it "updates existing price without creating a duplicate" do
    ProductSyncJob.perform_now(company_slug, csv_path)

    File.write(csv_path, <<~CSV)
      sku,name,price
      TEST-001,Test Widget One Updated,99.00
      TEST-002,Test Widget Two,10.00
      TEST-003,Test Widget Three,15.00
    CSV

    ProductSyncJob.perform_now(company_slug, csv_path)

    TenantConnection.switch(company_slug) do
      products = MasterProduct.where(sku: %w[TEST-001 TEST-002 TEST-003])
      expect(products.count).to eq(3)

      updated = MasterProduct.find_by(sku: "TEST-001")
      expect(updated.price).to eq(99.00)
      expect(updated.name).to eq("Test Widget One Updated")
    end
  end

  it "logs a warning and does not raise when CSV file is missing" do
    missing_path = "/tmp/does_not_exist_#{SecureRandom.hex}.csv"

    expect(Rails.logger).to receive(:warn).with(/CSV file not found/)

    expect {
      ProductSyncJob.perform_now(company_slug, missing_path)
    }.not_to raise_error
  end
end
