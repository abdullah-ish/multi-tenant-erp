class ExternalOrderReporter
  class ReportingError < StandardError; end

  ENDPOINT = ENV.fetch("ORDER_REPORT_URL", "https://external-erp.example.com/api/order_reports")
  API_TOKEN = ENV.fetch("ORDER_REPORT_API_TOKEN", "dummy-token")

  def initialize(order)
    @order = order
  end

  def report!
    begin
      response = connection.post(ENDPOINT) do |req|
        req.headers["Authorization"] = "Bearer #{API_TOKEN}"
        req.headers["Content-Type"]  = "application/json"
        req.body = payload.to_json
      end
    rescue Faraday::Error => e
      raise ReportingError, e.message
    end

    unless response.success?
      raise ReportingError, "External API returned #{response.status}: #{response.body}"
    end

    response
  rescue Faraday::ServerError, Faraday::ClientError => e
    raise ReportingError, e.message
  end

  private

  def payload
    {
      order_id:   @order.id,
      shop:       @order.shop.name,
      user_email: @order.user.email,
      status:     @order.status,
      total:      @order.total.to_s,
      items:      @order.order_items.map { |item| item_payload(item) },
      created_at: @order.created_at.iso8601
    }
  end

  def item_payload(item)
    {
      product_name:        item.shop_product.name,
      master_product_sku:  item.shop_product.master_product&.sku,
      quantity:            item.quantity,
      unit_price:          item.unit_price.to_s
    }
  end

  def connection
    Faraday.new do |f|
      f.request :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end
  end
end
