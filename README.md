# TenantKit

[![CI](https://github.com/wintan1418/tenant_kit/actions/workflows/ci.yml/badge.svg)](https://github.com/wintan1418/tenant_kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Row-level (shared-schema) multi-tenancy for Rails. One database, a tenant
foreign key on every owned table, automatic query scoping, and background-job
tenant propagation — built on `ActiveSupport::CurrentAttributes`, **strict by
default**.

## Why

Most Rails SaaS apps are multi-tenant. The row-level approach — a shared schema
with a tenant foreign key — is the simplest to operate and works cleanly with
every Rails default (Solid Queue / Cache / Cable, standard migrations,
connection pooling). TenantKit gives you that with safety rails:

- It **refuses** to run tenant-scoped queries when no tenant is set, rather than
  silently returning another tenant's data.
- It **carries the current tenant into background jobs**, so async work can't
  leak across tenants.
- It keeps the escape hatch **loud and greppable**: `TenantKit.without_tenant`.

Row-level isn't the only strategy — see [Why row-level](#why-row-level-and-not-the-others).

## Requirements

- Ruby `>= 3.3`
- Rails `>= 7.2` (primary target: 8.x)

## Installation

```ruby
# Gemfile
gem "tenant_kit"
```

```bash
bundle install
rails g tenant_kit:install
```

The installer writes `config/initializers/tenant_kit.rb` and, unless it already
exists, scaffolds the tenant model (`Account`) plus its migration. Pass
`--skip-tenant-model` if you already have one.

## Quick start

```ruby
# app/models/account.rb — the tenant model (does NOT call belongs_to_tenant)
class Account < ApplicationRecord
end

# app/models/project.rb — an owned model
class Project < ApplicationRecord
  belongs_to_tenant
  validates_uniqueness_to_tenant :slug
end
```

Add the tenant column to owned tables with the migration generator:

```bash
rails g tenant_kit:migration Project
# => db/migrate/XXXX_add_account_to_projects.rb
#    add_reference :projects, :account, null: false, foreign_key: true, index: true
```

Resolve the tenant per request in your controller:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  set_current_tenant_by_subdomain(:account, :subdomain)
end
```

Now `Project.all` returns only the current tenant's projects, and
`Project.create!(name: "X")` auto-assigns the current tenant.

## The current tenant

```ruby
TenantKit::Current.tenant            # => #<Account ...> or nil

TenantKit.with_tenant(account) do
  Project.count                      # scoped to `account`
end

TenantKit.without_tenant do
  Project.count                      # every tenant's projects
end
```

`with_tenant` and `without_tenant` always restore the previous state, even when
the block raises.

## Controller resolution helpers

Auto-included into `ActionController::Base` and `ActionController::API`.

```ruby
set_current_tenant_by_subdomain(:account, :subdomain)  # tenant.subdomain == request.subdomain
set_current_tenant_by_domain(:account, :domain)        # tenant.domain == request.host
set_current_tenant_by_header("X-Tenant-Id")            # for APIs (matches tenant.id)

# ...or fully custom:
set_current_tenant_through_filter
before_action :find_tenant
def find_tenant
  self.current_tenant = Account.find_by!(slug: params[:account_slug])
end
```

`current_tenant` is also exposed as a view helper.

## Background jobs

When `config.propagate_to_jobs` is on (the default), every `ActiveJob` captures
the current tenant at enqueue time and re-establishes it around `perform`. It
works with any queue adapter — the tenant's GlobalID is folded into the job's
serialized payload, so it survives Solid Queue too.

```ruby
TenantKit.with_tenant(account) do
  ReportJob.perform_later          # runs later, still scoped to `account`
end
```

Set `config.raise_on_missing_job_tenant = true` to make a job that was enqueued
with no tenant raise at perform instead of running unscoped.

## Configuration

```ruby
# config/initializers/tenant_kit.rb
TenantKit.configure do |config|
  config.tenant_class                = "Account"     # the tenant model
  config.tenant_column               = "account_id"  # FK on owned tables
  config.require_tenant              = true          # strict: raise when unscoped
  config.propagate_to_jobs           = true          # carry tenant into ActiveJob
  config.raise_on_missing_job_tenant = false         # job enqueued with no tenant
end
```

## Testing

```ruby
# spec/rails_helper.rb
require "tenant_kit/testing"

RSpec.configure do |config|
  config.include TenantKit::Testing
  config.after { TenantKit::Current.reset }
end
```

```ruby
it "scopes to the tenant" do
  as_tenant(account) do
    expect(Project.count).to eq(0)
  end
end
```

## Gotchas (read this)

- **`unscoped` bypasses tenant scoping.** Avoid it on tenant-owned models unless
  you mean it. Use `without_tenant` instead — explicit and greppable.
- **Action Cable / Turbo Streams are not auto-scoped.** Include the tenant in
  stream names — `stream_for [current_account, record]` — so broadcasts never
  cross tenants.
- **Console and seeds have no request, so no current tenant.** Wrap tenant work
  in `TenantKit.with_tenant(account) { ... }` or `TenantKit.without_tenant { }`.
- **Unique constraints must include the tenant column** at the database level:
  `add_index :projects, [:account_id, :slug], unique: true`. Pair it with
  `validates_uniqueness_to_tenant :slug` in the model.
- **Lead composite indexes with the tenant column:**
  `add_index :projects, [:account_id, :status]`.

## Why row-level (and not the others)

| Strategy | Isolation | Ops cost | Verdict |
|---|---|---|---|
| **Row-level (shared schema)** | Good (with discipline) | Low — one DB, one migration path | **Chosen** |
| Schema-per-tenant | Strong | High — migrations across N schemas, connection switching | Not in v1 |
| Database-per-tenant | Strongest | Highest — provision + migrate N databases | Not in v1 |

Row-level works cleanly with every Rails default and has exactly one migration
path. With strict scoping and database constraints it is safe enough for the
overwhelming majority of B2B SaaS.

## Roadmap (not in v1)

- Automatic Action Cable stream scoping
- Solid Cache tenant-aware caching helpers
- Schema-per-tenant / database-per-tenant modes

## Development

```bash
bin/setup          # or: bundle install
bundle exec rspec  # run the suite against spec/dummy
bundle exec rubocop
```

## Contributing

Bug reports and pull requests are welcome at
<https://github.com/wintan1418/tenant_kit>.

## License

Released under the [MIT License](MIT-LICENSE).
