# Multi-Tenant ERP Platform (Rails 7.2 API-Only)

A multi-tenant Enterprise Resource Planning (ERP) platform built with Rails 7.2 in API-only mode, PostgreSQL, and GoodJob. The application provides strict database-level tenant isolation, where each tenant operates within its own physical PostgreSQL database while a shared host database manages the tenant registry and background job coordination.

---

## Architectural Decisions

### 1. Database-Level Multi-Tenancy (Database-per-Tenant)
- **Host Database (`erp_host_<env>`)**: Stores tenant metadata (`companies` table) and centralized background job queues/cron jobs (`good_jobs` tables).
- **Tenant Databases (`erp_tenant_<slug>_<env>`)**: Each registered company gets a dedicated PostgreSQL database containing its operational data: `users`, `shops`, `master_products`, `shop_products`, `orders`, and `order_items`.
- **Strict Isolation**: Tenant databases have zero awareness of each other. Tenant models do not contain `company_id` foreign keys, eliminating any risk of cross-tenant data leakage through missed `where(company_id: ...)` scopes.

### 2. Tenant Identity & Connection Switching
- **User Ownership**: Users live strictly inside their tenant's database. There is no central cross-tenant users table.
- **Authentication Flow**:
  1. `POST /api/login` receives `{ company_slug, email, password }`.
  2. The controller queries `Company` in the host database to validate the slug.
  3. The connection switches to the tenant database to verify user credentials via `has_secure_password`.
  4. Upon success, a JWT is generated with `{ sub: user.id, slug: company.slug, exp: ... }`.
- **Zero Host Queries on Authenticated Requests**:
  - `TenantMiddleware` intercepts incoming requests, validates the JWT Bearer token, and extracts `slug`.
  - The middleware switches the database connection via `TenantConnection.switch(slug)` before request processing reaches controllers or models.
  - Subsequent queries hit only the tenant database.

### 3. Connection Switching: Why `Thread.current` instead of `connected_to`
Rails' native `connected_to(role: ...)` was evaluated and rejected for several critical reasons:
1. `connected_to` only routes models that explicitly inherit from a designated multi-db base class configured in Rails configuration files.
2. `ActiveRecord::Base.connection` inside a `connected_to` block still points to the host database.
3. Rails 7.2 migration runners and schema caches bind to default connection pools, causing DDL and schema lookups to target the wrong database.

**The Solution (`lib/tenant_connection.rb` & `TenantRecord`):**
- Connection pools for each tenant are created on-demand and cached in memory using dynamic abstract classes (`TenantDb<Slug> < ActiveRecord::Base`).
- `TenantConnection.switch(slug)` leases a connection from the tenant pool and assigns it to `Thread.current[:tenant_connection]` and `Thread.current[:tenant_pool]`.
- All tenant models inherit from `TenantRecord`, which overrides `.connection`, `.connection_pool`, and `.lease_connection` to return the thread-local tenant connection when active.
- Re-entrant / nested switches for the same tenant are handled idempotently to ensure outer blocks preserve their context.

### 4. Migration Isolation
- **Host Migrations (`db/migrate/`)**: Managed by standard Rails commands (`rails db:migrate`). Tracks host schemas (`companies`, GoodJob tables).
- **Tenant Migrations (`db/tenant_migrate/`)**: Excluded from the default Rails autoload path to prevent accidental execution against the host database.
- Tenant migrations are run programmatically during provisioning via `TenantConnection.provision!(slug)`, using `ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool` to isolate DDL execution to the target tenant database.

### 5. Domain Model & Product Catalog
- **Master Catalog vs Shop Products**:
  - `master_products`: Company-wide product catalog with unique `sku`, synchronized periodically via CSV imports.
  - `shop_products`: Products sold in individual retail shops. `master_product_id` is nullable (`optional: true`), allowing individual shops to offer custom products alongside master catalog items.
- **Indexes**:
  - `companies.slug` (unique)
  - `users.email` (unique per tenant)
  - `master_products.sku` (unique per tenant)
  - `shop_products` composite index: `[:shop_id, :master_product_id]`
  - `orders` composite index: `[:shop_id, :user_id]`, index on `:reported_at`
  - `order_items` index: `[:order_id]`

### 6. Background Jobs & Resilience (GoodJob)
- **Engine**: GoodJob using PostgreSQL advisory locks and cron scheduler (no Redis required).
- **Order Reporting (`OrderReportJob`)**:
  - Enqueued via `after_create_commit` on `Order` to ensure jobs are triggered only after database transaction commits (preventing phantom jobs on rolled-back transactions).
  - Uses eager loading scope `Order.with_report_payload` (`includes(:shop, :user, order_items: { shop_product: :master_product })`) to eliminate N+1 queries during payload generation.
  - Faraday HTTP client communicates with the external reporting endpoint. All network/server failures are caught and wrapped in `ExternalOrderReporter::ReportingError`, triggering GoodJob's `retry_on wait: :polynomially_longer, attempts: 5`.
  - Upon successful reporting, stamps `reported_at` on the order record.
- **Master Product Sync (`ProductSyncJob`)**:
  - Scheduled via GoodJob cron every 15 minutes per company (`config/initializers/good_job.rb`).
  - Reads tenant CSV files (`db/csv/<slug>_products.csv`) and executes high-performance batch upserts using `MasterProduct.upsert_all(rows, unique_by: :sku, update_only: [:name, :price, :synced_at])`.

---

## Getting Started

### Prerequisites
- Ruby 3.4+
- PostgreSQL running locally with user `postgres` and password `password` (or custom credentials configured via environment variables)

### Setup & Database Provisioning
1. Install dependencies:
   ```bash
   bundle install
   ```

2. Create and migrate the host database:
   ```bash
   rails db:create db:migrate
   ```

3. Provision and seed tenant databases (`acme` and `globex`):
   ```bash
   rails db:seed
   ```

4. Start the server:
   ```bash
   rails server -p 3000
   ```

---

## Seed Data & Credentials

The seed script creates two tenant databases: `erp_tenant_acme_development` and `erp_tenant_globex_development`.

| Tenant | Company Name | Email | Password |
|--------|--------------|-------|----------|
| `acme` | Acme Corp | `admin@acme.com` | `password123` |
| `globex` | Globex Inc | `admin@globex.com` | `password123` |

Each tenant database is seeded with:
- 1 Admin User
- 1 Main Shop
- 5 Master Products (synced from CSV)
- 5 Shop Products
- 1 Initial Sample Order

---

## Rails Console & Tenant Switching

When opening `rails console`, the session connects to the **Host DB** (`erp_host_development`) by default. Because `shops`, `users`, `orders`, and `products` live strictly inside their respective tenant databases, switch tenant contexts using these 1-liners:

### 1. Switch to Acme
```ruby
TenantConnection.switch!("acme")

Shop.pluck(:id, :name)
User.pluck(:id, :email)
Order.pluck(:id, :total)
MasterProduct.pluck(:sku, :price)
```

### 2. Switch to Globex
```ruby
TenantConnection.switch!("globex")

Shop.pluck(:id, :name)
User.pluck(:id, :email)
Order.pluck(:id, :total)
MasterProduct.pluck(:sku, :price)
```

### 3. Reset back to Host DB
```ruby
TenantConnection.reset!

Company.pluck(:id, :slug)
```

*Note: You can also scope queries using block syntax:*
```ruby
TenantConnection.switch("acme") do
  Shop.first.name
end
```

---

## API Documentation

### 1. Login (Public)
**`POST /api/login`**

#### Request
```json
{
  "company_slug": "acme",
  "email": "admin@acme.com",
  "password": "password123"
}
```

#### Response (`200 OK`)
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

#### Error Responses
- `401 Unauthorized`: `{ "error": "Company not found" }` or `{ "error": "Invalid credentials" }`

---

### 2. Create Order (Authenticated)
**`POST /api/orders`**

#### Headers
```
Authorization: Bearer <JWT_TOKEN>
Content-Type: application/json
```

#### Request
```json
{
  "order": {
    "shop_id": 1,
    "items": [
      { "shop_product_id": 1, "quantity": 2 },
      { "shop_product_id": 3, "quantity": 1 }
    ]
  }
}
```

#### Response (`201 Created`)
```json
{
  "order_id": 2,
  "status": "pending",
  "total": "44.97"
}
```

#### Error Responses
- `401 Unauthorized`: `{ "error": "Missing token" }` or `{ "error": "Signature has expired" }`
- `422 Unprocessable Entity`: `{ "errors": [...] }`

---

## Testing

Run the automated test suite with RSpec:
```bash
bundle exec rspec --format documentation
```

### Test Coverage Highlights
- **`spec/requests/sessions_spec.rb`**:
  - Valid authentication returning 200 + signed JWT
  - Verification of claims (`sub`, `slug`, `exp`)
  - 401 handling for invalid passwords and unrecognized tenant slugs
- **`spec/jobs/order_report_job_spec.rb`**:
  - Validates JSON payload and Bearer token transmission (WebMock)
  - Verification of `reported_at` timestamp persistence on success
  - Verification that HTTP 500 errors raise `ReportingError` to trigger polynomial retry
- **`spec/jobs/product_sync_job_spec.rb`**:
  - Batch creation of master products from fixture CSV
  - Idempotent upsert verification (price update without duplicate records)
  - Missing CSV handling (logs warning without uncaught exceptions)
