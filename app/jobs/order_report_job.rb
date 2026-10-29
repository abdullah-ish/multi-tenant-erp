class OrderReportJob < ApplicationJob
  queue_as :default

  retry_on ExternalOrderReporter::ReportingError,
           wait:     :polynomially_longer,
           attempts: 5

  def perform(order_id, company_slug)
    TenantConnection.switch(company_slug) do
      order = Order.with_report_payload.find(order_id)
      reporter = ExternalOrderReporter.new(order)
      reporter.report!
      order.update_columns(reported_at: Time.current)
    end
  end
end
