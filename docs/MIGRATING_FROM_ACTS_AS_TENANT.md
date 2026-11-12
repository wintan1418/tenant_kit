# Migrating from acts_as_tenant

Both gems use the same strategy (a tenant foreign key plus a strict
`default_scope`) and a similar API, so a migration is mostly renames. Check
[COMPARISON.md](COMPARISON.md) first: acts_as_tenant has features TenantKit
doesn't (`through:`, polymorphic tenants, Sidekiq middleware, lambda
`require_tenant`). If you rely on those, stay put or plan replacements.

## API mapping

| acts_as_tenant | TenantKit | Notes |
|---|---|---|
| `acts_as_tenant(:account)` | `belongs_to_tenant(:account)` | Options: `class_name:`, `foreign_key:`, `optional:`, `inverse_of:`. Don't also declare `belongs_to :account`. |
| `acts_as_tenant(:account, through: ...)` | — | Not supported. |
| `acts_as_tenant(:account, polymorphic: true)` | — | Not supported. |
| `validates_uniqueness_to_tenant :name` | `validates_uniqueness_to_tenant :name` | Same; call it after `belongs_to_tenant`. |
| `ActsAsTenant.current_tenant` | `TenantKit::Current.tenant` | |
| `ActsAsTenant.current_tenant = x` | `TenantKit::Current.tenant = x` | Prefer the block form. |
| `ActsAsTenant.with_tenant(x) { }` | `TenantKit.with_tenant(x) { }` | Always scoped, even inside `without_tenant`. |
| `ActsAsTenant.without_tenant { }` | `TenantKit.without_tenant { }` | |
| `ActsAsTenant.with_mutable_tenant { }` | `TenantKit.without_tenant { }` | Changing a persisted record's tenant is allowed only with scoping disabled. |
| `config.require_tenant = true` | `config.require_tenant = true` | Boolean only (no lambda). |
| `config.require_tenant = ->(...) { }` | — | Use `without_tenant` at the call sites that are allowed to be unscoped. |
| `set_current_tenant_by_subdomain(:account, :subdomain)` | `set_current_tenant_by_subdomain(:account, :subdomain)` | Same arguments. TenantKit matches `request.subdomain`. |
| `set_current_tenant_by_subdomain_or_domain` | `set_current_tenant_through_filter` + your own `before_action` | |
| — | `set_current_tenant_by_domain`, `set_current_tenant_by_header` | |
| `set_current_tenant_through_filter` + `set_current_tenant(x)` | `set_current_tenant_through_filter` + `self.current_tenant = x` | |
| `current_tenant` (controller/view helper) | `current_tenant` | |
| `ActsAsTenant.test_tenant` + `TestTenantMiddleware` | `TenantKit.with_tenant` / `as_tenant` from `TenantKit::Testing` | |
| `require "acts_as_tenant/sidekiq"` | ActiveJob propagation (on by default) | Plain Sidekiq workers (not ActiveJob) are not covered. |
| `config.job_scope` | — | Tenant is located by GlobalID. |
| `ActsAsTenant::Errors::NoTenantSet` | `TenantKit::NoTenantSet` | |
| `config.tenant_change_hook` | — | Use `ActiveSupport::CurrentAttributes` callbacks on your own `Current`. |

## Steps

1. **Add TenantKit next to acts_as_tenant** and run the installer without
   creating a tenant model:

   ```bash
   bundle add tenant_kit
   rails g tenant_kit:install --skip-tenant-model
   ```

   Set `config.tenant_class` / `config.tenant_column` in
   `config/initializers/tenant_kit.rb` to match your tenant (e.g. `"Account"` /
   `"account_id"`).

2. **Wrap the tenant API in one place** (if you haven't already) so the switch
   is a small diff:

   ```ruby
   # app/models/current.rb
   class Current < ActiveSupport::CurrentAttributes
     def self.account = TenantKit::Current.tenant
     def self.with_account(account, &block) = TenantKit.with_tenant(account, &block)
     def self.unscoped(&block) = TenantKit.without_tenant(&block)
   end
   ```

3. **Swap the macros**, model by model or all at once:
   `acts_as_tenant(:account)` → `belongs_to_tenant(:account)`. Leave
   `validates_uniqueness_to_tenant` as is. Search-and-replace
   `ActsAsTenant.with_tenant` / `without_tenant` / `current_tenant` with the
   table above.

4. **Swap the controller helpers** (same names for subdomain and through-filter;
   `set_current_tenant(x)` becomes `self.current_tenant = x`).

5. **Jobs.** ActiveJob jobs need no changes. Note one difference: TenantKit
   raises `TenantKit::TenantMismatch` if a job is given a tenant-owned record
   from a different tenant than it was enqueued under. Plain Sidekiq workers
   need their own tenant handling (pass the tenant id and use
   `TenantKit.with_tenant`).

6. **Review the stricter writes.** TenantKit additionally rejects:
   `insert_all` / `upsert_all` rows naming another tenant (`CrossTenantWrite`),
   `update_counters` on another tenant's id (scoped), and conditions that try to
   replace the tenant condition (`other_account.projects`, `rewhere`). Run your
   suite; failures here usually point at real cross-tenant access worth a look.
   `config.prevent_cross_tenant_writes = false` restores permissive saves while
   you migrate.

7. **Tests.** Replace `ActsAsTenant.test_tenant` with `TenantKit.with_tenant`
   (or `as_tenant` from `TenantKit::Testing`), and reset between examples:

   ```ruby
   require "tenant_kit/testing"
   RSpec.configure do |config|
     config.include TenantKit::Testing
     config.after { TenantKit::Current.reset }
   end
   ```

8. **Remove acts_as_tenant** from the Gemfile and its initializer once nothing
   references it (`grep -rn ActsAsTenant app lib config spec`).

No data or schema migration is needed: both gems use the same `account_id`
column and indexes.
