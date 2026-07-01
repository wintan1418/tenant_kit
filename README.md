# TenantKit

Row-level (shared-schema) multi-tenancy for Rails 8. One database, a `tenant_id`
on every owned table, automatic query scoping, and background-job tenant
propagation — built on `ActiveSupport::CurrentAttributes`, strict by default.

> This README is a skeleton. Fill in badges, exact install steps, and the final
> API once the gem is built per `MASTER_BUILD.md`.

## Why

Most Rails SaaS apps are multi-tenant. The row-level approach — a shared schema
with a tenant foreign key — is the simplest to operate and works cleanly with
every Rails 8 default (Solid Queue/Cache/Cable). TenantKit gives you that with
safety rails: it refuses to run tenant-scoped queries when no tenant is set,
rather than silently returning another tenant's data, and it carries the current
tenant into background jobs so async work can't leak across tenants.

## Installation

```ruby
# Gemfile
gem "tenant_kit"
```

```bash
bundle install
rails g tenant_kit:install
```

## Quick start

```ruby
# app/models/account.rb  — the tenant model (does NOT call belongs_to_tenant)
class Account < ApplicationRecord
end

# app/models/project.rb  — an owned model
class Project < ApplicationRecord
  belongs_to_tenant
  validates_uniqueness_to_tenant :slug
end
```

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  set_current_tenant_by_subdomain(:account, :subdomain)
end
```

Now `Project.all` returns only the current tenant's projects, and
`Project.create!(name: "X")` auto-assigns the current tenant.

## Working outside a tenant

```ruby
TenantKit.without_tenant do
  Project.count      # every tenant's projects — for admin, seeds, migrations
end

TenantKit.with_tenant(some_account) do
  Project.count      # scoped to some_account
end
```

## Configuration

```ruby
# config/initializers/tenant_kit.rb
TenantKit.configure do |config|
  config.tenant_class          = "Account"
  config.tenant_column         = "account_id"
  config.require_tenant        = true
  config.propagate_to_jobs     = true
  config.raise_on_missing_job_tenant = false
end
```

## Gotchas (read this)

- **`unscoped` bypasses tenant scoping.** Avoid it on tenant-owned models unless
  you mean it. Use `without_tenant` instead, which is explicit and greppable.
- **Action Cable / Turbo Streams are not auto-scoped.** Include the tenant in
  stream names — `stream_for [current_account, record]` — so broadcasts never
  cross tenants.
- **Console and seeds have no request, so no current tenant.** Wrap tenant work
  in `TenantKit.with_tenant(account) { ... }` or `TenantKit.without_tenant { }`.
- **Unique constraints must include the tenant column** at the database level:
  `add_index :projects, [:account_id, :slug], unique: true`.

## Roadmap (not in v1)

- Automatic Action Cable stream scoping
- Solid Cache tenant-aware caching helpers
- Schema-per-tenant / database-per-tenant modes

## License

MIT.
