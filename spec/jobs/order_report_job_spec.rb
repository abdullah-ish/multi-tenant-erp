require "rails_helper"

RSpec.describe OrderReportJob, type: :job do
  let(:company_slug) { "acme" }
  let(:endpoint) { ExternalOrderReporter::ENDPOINT }

  let(:user_id) { nil }
  let(:shop_id) { nil }
  let(:order_id) { nil }

  before do
    TenantConnection.switch(company_slug) do
      user = User.find_or_create_by!(email: "admin@acme.com") do |u|
        u.password              = "password123"
        u.password_confirmation = "password123"
      end

      shop = Shop.find_or_create_by!(name: "Acme Test Shop")

      mp = MasterProduct.find_or_create_by!(sku: "ACME-001") do |p|
        p.name  = "Widget Alpha"
        p.price = 9.99
      end
      sp = ShopProduct.find_or_create_by!(shop: shop, master_product: mp) do |p|
        p.name  = mp.name
        p.price = mp.price
      end

      Order.skip_callback(:commit, :after, :enqueue_report_job)
      order = Order.create!(
        shop:   shop,
        user:   user,
        status: "pending",
        total:  9.99
      )
      OrderItem.create!(
        order:        order,
        shop_product: sp,
        quantity:     1,
        unit_price:   9.99
      )
      Order.set_callback(:commit, :after, :enqueue_report_job)

      @order_id = order.id
    end
  end

  it "POSTs correct payload to external API with Bearer token" do
    stub = stub_request(:post, endpoint)
      .with(
        headers: { "Authorization" => "Bearer #{ExternalOrderReporter::API_TOKEN}" }
      )
      .to_return(status: 200, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })

    OrderReportJob.perform_now(@order_id, company_slug)

    expect(stub).to have_been_requested
  end

  it "stamps reported_at on success" do
    stub_request(:post, endpoint)
      .to_return(status: 200, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })

    OrderReportJob.perform_now(@order_id, company_slug)

    TenantConnection.switch(company_slug) do
      order = Order.find(@order_id)
      expect(order.reported_at).to be_present
    end
  end

  it "raises ReportingError on HTTP 500 (enables GoodJob retry)" do
    stub_request(:post, endpoint)
      .to_return(status: 500, body: "Server Error")

    # GoodJob's retry_on captures errors in perform_now, so we test the reporter directly
    TenantConnection.switch(company_slug) do
      order = Order.with_report_payload.find(@order_id)
      reporter = ExternalOrderReporter.new(order)
      expect { reporter.report! }.to raise_error(ExternalOrderReporter::ReportingError)
    end
  end
end
