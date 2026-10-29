module TenantHelpers
  def with_tenant(slug, &block)
    TenantConnection.switch(slug, &block)
  end
end

RSpec.configure do |config|
  config.include TenantHelpers
end
