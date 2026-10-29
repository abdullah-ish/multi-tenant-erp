Rails.application.configure do
  config.good_job.execution_mode          = :async
  config.good_job.poll_interval           = 30
  config.good_job.shutdown_timeout        = 25
  config.good_job.enable_cron             = true

  config.good_job.cron = {
    product_sync_acme: {
      cron:   "*/15 * * * *",
      class:  "ProductSyncJob",
      args:   [ "acme" ],
      description: "Sync Acme products every 15 minutes"
    },
    product_sync_globex: {
      cron:   "*/15 * * * *",
      class:  "ProductSyncJob",
      args:   [ "globex" ],
      description: "Sync Globex products every 15 minutes"
    }
  }
end
