class TenantRecord < ActiveRecord::Base
  self.abstract_class = true

  def self.connection
    Thread.current[:tenant_connection] || super
  end

  def self.connection_pool
    Thread.current[:tenant_pool] || super
  end

  def self.lease_connection
    Thread.current[:tenant_connection] || super
  end
end
