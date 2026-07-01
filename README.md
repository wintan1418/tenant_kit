<div align="center">

<img src="assets/banner.svg" alt="TenantKit — row-level multi-tenancy for Rails, strict by default" width="100%">

<br>

*One database. A tenant foreign key on every owned table. Automatic query scoping. No cross-tenant leaks — not even in your jobs.*

[![Gem Version](https://img.shields.io/gem/v/tenant_kit?color=e9573f&label=gem&logo=rubygems)](https://rubygems.org/gems/tenant_kit)
[![Downloads](https://img.shields.io/gem/dt/tenant_kit?color=blue&logo=rubygems)](https://rubygems.org/gems/tenant_kit)
[![CI](https://github.com/wintan1418/tenant_kit/actions/workflows/ci.yml/badge.svg)](https://github.com/wintan1418/tenant_kit/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.3-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%207.2-CC0000?logo=rubyonrails&logoColor=white)](https://rubyonrails.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

</div>

---

```ruby
class Project < ApplicationRecord
  belongs_to_tenant                      # ← scoped, auto-assigned, validated
  validates_uniqueness_to_tenant :slug   # ← unique *per tenant*
end

TenantKit.with_tenant(acme) { Project.count }   # → only Acme's projects
Project.count                                   # → raises 💥 NoTenantSet (no silent leaks)
```

## ✨ Why TenantKit

Most Rails SaaS apps are multi-tenant. The **row-level** approach — a shared schema with a tenant foreign key — is the simplest to operate and works cleanly with every Rails default (Solid Queue / Cache / Cable, standard migrations, connection pooling). TenantKit gives you that, with safety rails most tenancy gems leave off:

|  | What you get |
|---|---|
| 🔒 **Strict by default** | Queries with no current tenant **raise** instead of silently returning another tenant's rows. |
| ⚙️ **Automatic scoping** | `belongs_to_tenant` scopes every read, auto-assigns the tenant on create, and validates its presence. |
| 📨 **Job propagation** | The current tenant rides into `ActiveJob` via GlobalID and is restored around `perform` — survives Solid Queue. |
| 🧭 **Request resolution** | One-liners to resolve the tenant by subdomain, domain, header, or your own filter. |
| 🔁 **Unique-per-tenant** | `validates_uniqueness_to_tenant` folds the tenant into the uniqueness scope. |
| 🚪 **Loud escape hatch** | `TenantKit.without_tenant { }` — explicit, greppable, auditable in review. |
| 🪶 **Featherweight** | Zero runtime deps beyond Rails. Built on `ActiveSupport::CurrentAttributes` — never a raw thread-local. |

## 📖 Table of contents

- [Requirements](#-requirements)
- [Installation](#-installation)
- [Quick start](#-quick-start)
- [The current tenant](#-the-current-tenant)
- [Controller resolution](#-controller-resolution)
- [Background jobs](#-background-jobs)
- [Configuration](#-configuration)
- [Testing](#-testing)
- [Gotchas](#-gotchas-read-this)
- [Why row-level?](#-why-row-level-and-not-the-others)
- [Roadmap](#-roadmap)
- [Development & contributing](#-development)

## 📋 Requirements

- **Ruby** `>= 3.3`
- **Rails** `>= 7.2` (primary target: **8.x**)

## 💎 Installation

```ruby
# Gemfile
gem "tenant_kit"
```

```bash
bundle install
rails g tenant_kit:install
```

The installer writes `config/initializers/tenant_kit.rb` and, unless one already exists, scaffolds the tenant model (`Account`) plus its migration. Pass `--skip-tenant-model` if you already have one.

## 🚀 Quick start

**1. Mark your owned models.** The tenant model itself does *not* call `belongs_to_tenant`.

```ruby
# app/models/account.rb — the tenant
class Account < ApplicationRecord
end

# app/models/project.rb — owned by a tenant
class Project < ApplicationRecord
  belongs_to_tenant
  validates_uniqueness_to_tenant :slug
end
```

**2. Add the tenant column** with the migration generator:

```bash
rails g tenant_kit:migration Project
# => add_reference :projects, :account, null: false, foreign_key: true, index: true
```

**3. Resolve the tenant per request:**

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  set_current_tenant_by_subdomain(:account, :subdomain)
end
```

That's it. `Project.all` now returns only the current tenant's projects, and `Project.create!(name: "X")` auto-assigns the current tenant. 🎉

## 🧭 The current tenant

```ruby
TenantKit::Current.tenant            # => #<Account ...> or nil

TenantKit.with_tenant(account) do
  Project.count                      # scoped to `account`
end

TenantKit.without_tenant do
  Project.count                      # every tenant's projects
end
```

`with_tenant` and `without_tenant` **always restore** the previous state — even when the block raises.

## 🎯 Controller resolution

Auto-included into `ActionController::Base` and `ActionController::API`.

```ruby
set_current_tenant_by_subdomain(:account, :subdomain)  # tenant.subdomain == request.subdomain
set_current_tenant_by_domain(:account, :domain)        # tenant.domain    == request.host
set_current_tenant_by_header("X-Tenant-Id")            # for APIs (matches tenant.id)

# …or fully custom:
set_current_tenant_through_filter
before_action :find_tenant

def find_tenant
  self.current_tenant = Account.find_by!(slug: params[:account_slug])
end
```

`current_tenant` is also exposed as a view helper.

## 📨 Background jobs

With `config.propagate_to_jobs` on (the default), every `ActiveJob` captures the current tenant at **enqueue** time and re-establishes it around **perform**. The tenant's GlobalID is folded into the job's serialized payload, so it survives *any* queue adapter — Solid Queue included.

```ruby
TenantKit.with_tenant(account) do
  ReportJob.perform_later      # runs later, in another process, still scoped to `account`
end
```

Set `config.raise_on_missing_job_tenant = true` to make a job that was enqueued with no tenant **raise** at perform instead of running unscoped.

## ⚙️ Configuration

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

## 🧪 Testing

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

## ⚠️ Gotchas (read this)

> These are the sharp edges of *any* row-level tenancy setup. TenantKit makes them safe — as long as you know they exist.

- **`unscoped` bypasses tenant scoping.** Avoid it on owned models unless you mean it. Reach for `without_tenant` instead — explicit and greppable.
- **Action Cable / Turbo Streams are not auto-scoped.** Put the tenant in stream names — `stream_for [current_account, record]` — so broadcasts never cross tenants.
- **Console & seeds have no request**, so no current tenant. Wrap work in `TenantKit.with_tenant(account) { … }` or `TenantKit.without_tenant { }`.
- **Unique constraints must include the tenant column** at the DB level: `add_index :projects, [:account_id, :slug], unique: true`. Pair it with `validates_uniqueness_to_tenant :slug`.
- **Lead composite indexes with the tenant column:** `add_index :projects, [:account_id, :status]`.

## 🤔 Why row-level (and not the others)?

| Strategy | Isolation | Ops cost | Verdict |
|---|:---:|:---:|:---:|
| **Row-level** (shared schema) | Good *(with discipline)* | 🟢 Low — one DB, one migration path | ✅ **Chosen** |
| Schema-per-tenant | Strong | 🟠 High — migrations across N schemas, connection switching | ❌ Not in v1 |
| Database-per-tenant | Strongest | 🔴 Highest — provision + migrate N databases | ❌ Not in v1 |

Row-level works cleanly with every Rails default and has exactly **one** migration path. With strict scoping and database constraints it is safe enough for the overwhelming majority of B2B SaaS.

## 🗺️ Roadmap

Not in v1 — tracked for future releases:

- [ ] Automatic Action Cable stream scoping
- [ ] Solid Cache tenant-aware caching helpers
- [ ] Schema-per-tenant / database-per-tenant modes

## 🛠️ Development

```bash
bin/setup           # or: bundle install
bundle exec rspec   # run the suite against spec/dummy
bundle exec rubocop # lint
```

## 🤝 Contributing

Bug reports and pull requests are welcome at **[github.com/wintan1418/tenant_kit](https://github.com/wintan1418/tenant_kit)**. Open an issue to discuss anything substantial before you build it.

## 📄 License

Released under the [MIT License](MIT-LICENSE).

<div align="center">

---

**[⬆ back to top](#-why-tenantkit)**

Built with ❤️ for Rails SaaS teams.

</div>
