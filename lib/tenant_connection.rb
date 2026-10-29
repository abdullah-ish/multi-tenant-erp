require "pg"

module TenantConnection
  @@pool_cache = {}
  @@pool_mutex = Mutex.new

  PUBLIC_PATHS = %w[/api/login].freeze

  def self.clear_pool_cache!
    @@pool_mutex.synchronize { @@pool_cache.clear }
  end

  def self.switch!(slug)
    pool = pool_for(slug)
    Thread.current[:tenant_connection] = pool.connection
    Thread.current[:tenant_pool]       = pool
    Thread.current[:tenant_slug]       = slug
    "Switched to #{slug} (#{db_name(slug)})"
  end

  def self.reset!
    Thread.current[:tenant_connection] = nil
    Thread.current[:tenant_pool]       = nil
    Thread.current[:tenant_slug]       = nil
    "Reset to Host DB"
  end

  def self.switch(slug, &block)
    # Support re-entrant calls for the same tenant without double-wrapping
    if Thread.current[:tenant_connection] && Thread.current[:tenant_slug] == slug
      return yield
    end

    pool = pool_for(slug)
    pool.with_connection do |conn|
      previous_conn = Thread.current[:tenant_connection]
      previous_pool = Thread.current[:tenant_pool]
      previous_slug = Thread.current[:tenant_slug]

      Thread.current[:tenant_connection] = conn
      Thread.current[:tenant_pool]       = pool
      Thread.current[:tenant_slug]       = slug
      yield
    ensure
      Thread.current[:tenant_connection] = previous_conn
      Thread.current[:tenant_pool]       = previous_pool
      Thread.current[:tenant_slug]       = previous_slug
    end
  end

  MIGRATION_MUTEX = Mutex.new

  def self.provision!(slug)
    MIGRATION_MUTEX.synchronize do
      create_database_raw!(slug)
      run_migrations!(slug)
    end
  end

  def self.db_name(slug)
    env = Rails.env
    "erp_tenant_#{slug}_#{env}"
  end

  private

  def self.pool_for(slug)
    @@pool_mutex.synchronize do
      @@pool_cache[slug] ||= build_pool(slug)
    end
  end

  def self.build_pool(slug)
    db_config = ActiveRecord::Base.connection_pool.db_config
    spec = {
      adapter:  "postgresql",
      encoding: "unicode",
      pool:     ENV.fetch("DB_POOL") { 10 }.to_i,
      username: db_config.configuration_hash[:username] || ENV["DB_USERNAME"] || "postgres",
      password: db_config.configuration_hash[:password] || ENV["DB_PASSWORD"] || "password",
      host:     db_config.configuration_hash[:host]     || "localhost",
      port:     (db_config.configuration_hash[:port]    || 5432).to_i,
      database: db_name(slug),
      idle_timeout: ENV.fetch("DB_IDLE_TIMEOUT") { 900 }.to_i
    }

    klass_name = "TenantDb#{slug.camelize}"
    unless Object.const_defined?(klass_name)
      klass = Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end
      Object.const_set(klass_name, klass)
    end

    klass = Object.const_get(klass_name)
    klass.establish_connection(spec)
    klass.connection_pool
  end

  def self.create_database_raw!(slug)
    db_name_val = db_name(slug)
    db_config   = ActiveRecord::Base.connection_pool.db_config.configuration_hash

    conn = PG.connect(
      host:     db_config[:host]     || "localhost",
      port:     (db_config[:port]    || 5432).to_i,
      user:     db_config[:username] || "postgres",
      password: db_config[:password] || "password",
      dbname:   "postgres"
    )

    result = conn.exec_params(
      "SELECT 1 FROM pg_database WHERE datname = $1",
      [ db_name_val ]
    )

    if result.ntuples == 0
      conn.exec("CREATE DATABASE \"#{db_name_val}\"")
      Rails.logger.info "[TenantConnection] Created database: #{db_name_val}"
    else
      Rails.logger.info "[TenantConnection] Database already exists: #{db_name_val}"
    end
  ensure
    conn&.finish
  end

  def self.run_migrations!(slug)
    tenant_db_spec = {
      adapter:  "postgresql",
      encoding: "unicode",
      pool:     2,
      username: host_db_config[:username] || ENV["DB_USERNAME"] || "postgres",
      password: host_db_config[:password] || ENV["DB_PASSWORD"] || "password",
      host:     host_db_config[:host]     || "localhost",
      port:     (host_db_config[:port]    || 5432).to_i,
      database: db_name(slug)
    }

    db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
      Rails.env, "tenant_#{slug}", tenant_db_spec
    )

    ActiveRecord::Tasks::DatabaseTasks.send(:with_temporary_pool, db_config) do |tmp_pool|
      schema_migration  = ActiveRecord::SchemaMigration.new(tmp_pool)
      internal_metadata = ActiveRecord::InternalMetadata.new(tmp_pool)

      ctx = ActiveRecord::MigrationContext.new(
        Rails.root.join("db/tenant_migrate").to_s,
        schema_migration,
        internal_metadata
      )
      ctx.migrate
      Rails.logger.info "[TenantConnection] Migrations ran for tenant: #{slug}"
    end
  end

  def self.host_db_config
    ActiveRecord::Base.connection_pool.db_config.configuration_hash
  end
  private_class_method :host_db_config
end
