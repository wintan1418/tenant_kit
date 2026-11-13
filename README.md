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
<br>
[![Tested](https://img.shields.io/badge/tested-Ruby%203.3%2F3.4%20%C3%97%20Rails%207.2%2F8.0%2F8.1%20%C3%97%20SQLite%2FPostgreSQL%2FMySQL-2ea44f)](.github/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/line%20coverage-%E2%89%A590%25%20enforced-2ea44f)](spec/spec_helper.rb)
[![Guarantees](https://img.shields.io/badge/isolation-guarantees%20%2B%20leak%20suite-blueviolet)](docs/GUARANTEES.md)
[![Security policy](https://img.shields.io/badge/security-policy-informational)](SECURITY.md)

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
| 🧱 **Write guards** | Saving under another tenant, moving a record between tenants, `insert_all`/`upsert_all` rows for other tenants, and `update_counters` on foreign ids are all refused. |
| 📡 **Realtime** | Tenant-prefixed Turbo Streams / Action Cable names, broadcasts and subscription checks. |
| 🛡️ **Optional Postgres RLS** | Let the database enforce the boundary too — even for raw SQL. |
| 🧪 **Proven** | An adversarial [leak suite](spec/leaks) and a [guarantees document](docs/GUARANTEES.md) that links every claim to its spec. |
| 🪶 **Featherweight** | Zero runtime deps beyond Rails. Built on `ActiveSupport::CurrentAttributes` — never a raw thread-local. |

## 📖 Table of contents

- [Requirements](#-requirements)
- [Installation](#-installation)
- [Quick start](#-quick-start)
- [The current tenant](#-the-current-tenant)
- [Controller resolution](#-controller-resolution)
- [Background jobs](#-background-jobs)
- [What's guaranteed](#-whats-guaranteed)
- [Cross-tenant writes](#-cross-tenant-writes)
- [Turbo Streams & Action Cable](#-turbo-streams--action-cable)
- [Explicit scoping mode](#-explicit-scoping-mode)
- [PostgreSQL Row-Level Security](#-postgresql-row-level-security-optional)
- [Configuration](#-configuration)
- [Testing](#-testing)
- [Gotchas](#-gotchas-read-this)
- [Why `default_scope`?](#-why-default_scope)
- [Why row-level?](#-why-row-level-and-not-the-others)
- [Used in production](#-used-in-production)
- [Documentation](#-documentation)
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

`with_tenant` and `without_tenant` **always restore** the previous state — even when the block raises. `with_tenant` always scopes, even when nested inside `without_tenant`.

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

The tenant is established around `perform_now`, so argument deserialization, callbacks and retries (`retry_on`) all run under it. Mailers sent with `deliver_later` are jobs too, so they render under the right tenant.

GlobalID locates job arguments with `unscoped`, so TenantKit checks them: a tenant-owned record argument that belongs to a **different** tenant raises `TenantKit::TenantMismatch` before `perform` (`config.verify_job_arguments`).

Set `config.raise_on_missing_job_tenant = true` to make a job that was enqueued with no tenant **raise** at perform instead of running unscoped.

## ✅ What's guaranteed

[`docs/GUARANTEES.md`](docs/GUARANTEES.md) is the contract: every isolation guarantee — reads, associations, joins and preloading, bulk and by-id writes, `insert_all`/`upsert_all`, counters, nested attributes, STI, polymorphic models, jobs, mailers, threads, fibers, the Rails executor, realtime, RLS — links to the spec that proves it, and an explicit **"not guaranteed / your responsibility"** list covers the rest (`unscoped`, raw SQL, `update_columns`, signed ids, Active Storage tables, caches...).

The proofs live in [`spec/leaks/`](spec/leaks): adversarial specs that act as one tenant and try to reach another.

## 🧱 Cross-tenant writes

Reads are scoped; writes are guarded too (`config.prevent_cross_tenant_writes`, on by default):

```ruby
TenantKit.with_tenant(acme) do
  Project.create(name: "x", account_id: globex.id)  # invalid: "must be the current tenant"
  project.update(account: globex)                    # invalid: "cannot be changed to another tenant"
  Project.insert_all([{ name: "x", account_id: globex.id }])  # raises TenantKit::CrossTenantWrite
  Project.insert_all([{ name: "x" }])                # account_id filled in for you
  Project.update_counters(globex_project.id, tasks_count: 1)  # 0 rows: scoped to acme
  globex.projects                                    # empty — the tenant condition can't be replaced
end

TenantKit.without_tenant { project.update!(account: globex) }  # moving tenants: explicit
```

`update_column(s)` skip validations; set `config.scope_record_writes = true` to also put the tenant condition on record-level `UPDATE`/`DELETE`.

## 📡 Turbo Streams & Action Cable

Broadcasts reach everyone subscribed to a stream name, so TenantKit puts the tenant first in every name it builds.

```ruby
class Project < ApplicationRecord
  belongs_to_tenant
  broadcasts_to_tenant            # stream [project.account, "projects"]; enqueued under the record's tenant
end
```

```erb
<%= turbo_stream_from_tenant "projects" %>                     <%# current tenant's stream %>
<%= turbo_stream_from_tenant "projects", channel: TenantStreamsChannel %>
```

```ruby
class TenantStreamsChannel < Turbo::StreamsChannel
  include TenantKit::Turbo::StreamsChannel   # rejects other tenants' signed stream names
end

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include TenantKit::Cable::Connection     # every command runs under current_tenant
    identified_by :current_tenant
    def connect = self.current_tenant = Account.find_by!(subdomain: request.subdomain)
  end

  class Channel < ActionCable::Channel::Base
    include TenantKit::Cable::Channel        # stream_for_tenant, broadcast_to_tenant, reject_unless_current_tenant_owns
  end
end

class ProjectChannel < ApplicationCable::Channel
  def subscribed = stream_for_tenant(Project.find(params[:id]))
end
ProjectChannel.broadcast_to_tenant(account, project, { html: "..." })
```

`TenantKit::Streams.stream_name(*streamables)` builds the same names directly (identical format to turbo-rails). turbo-rails is optional and only needed for the Turbo helpers.

## 🎛️ Explicit scoping mode

Prefer opt-in scoping at the call site? Declare the model explicit — no `default_scope`:

```ruby
class Note < ApplicationRecord
  belongs_to_tenant scoping: :explicit
end

Note.for_current_tenant.where(pinned: true)   # scoped
Note.where(pinned: true).to_a                 # raises TenantKit::ExplicitScopeMissing in dev/test, logs in production
current_account.notes                         # fine: association reads carry the tenant condition
```

Explicit scoping fails *open* when someone forgets, so the guard (`config.explicit_scoping_guard`: `:raise` / `:log` / `false`) is what keeps it honest. Auto-assignment and every write guard still apply. The default mode is unchanged.

## 🛡️ PostgreSQL Row-Level Security (optional)

Let PostgreSQL enforce the boundary underneath Active Record — so even `find_by_sql`, `unscoped` and hand-written SQL only see the current tenant:

```bash
rails g tenant_kit:rls     # migration: ENABLE + FORCE RLS and a tenant policy on every owned table
```

```ruby
config.postgres_rls = true
config.postgres_rls_strategy = :session   # or :transaction behind PgBouncer transaction pooling
```

TenantKit applies `tenant_kit.tenant_id` on each connection right before SQL runs (only when it changes). The app must connect as a role **without** `SUPERUSER`/`BYPASSRLS`. Strategies, PgBouncer, the `without_tenant` bypass and trade-offs: **[docs/POSTGRES_RLS.md](docs/POSTGRES_RLS.md)**.

## ⚙️ Configuration

```ruby
# config/initializers/tenant_kit.rb
TenantKit.configure do |config|
  config.tenant_class                = "Account"     # the tenant model
  config.tenant_column               = "account_id"  # FK on owned tables
  config.require_tenant              = true          # strict: raise when unscoped
  config.propagate_to_jobs           = true          # carry tenant into ActiveJob
  config.raise_on_missing_job_tenant = false         # job enqueued with no tenant
  config.verify_job_arguments        = true          # reject other tenants' records as job args
  config.prevent_cross_tenant_writes = true          # refuse saves/moves/inserts across tenants
  config.scope_record_writes         = false         # tenant condition on record-level UPDATE/DELETE
  config.explicit_scoping_guard      = nil           # explicit mode: :raise in dev/test, :log elsewhere
  config.postgres_rls                = false         # PostgreSQL Row-Level Security integration
  config.postgres_rls_strategy       = :session      # or :transaction (PgBouncer transaction mode)
  config.postgres_rls_bypass         = true          # without_tenant sets tenant_kit.bypass
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
- **Raw SQL and `update_column(s)` are not scoped** by Active Record. Build SQL from scoped relations, or enable [PostgreSQL RLS](docs/POSTGRES_RLS.md).
- **Plain `stream_from` / `broadcasts_to` aren't tenant-aware.** Use the [Turbo & Action Cable helpers](#-turbo-streams--action-cable).
- **Active Storage, Action Text and caches are global.** Reach attachments through their tenant-owned record; put the tenant in cache keys.
- **Console & seeds have no request**, so no current tenant. Wrap work in `TenantKit.with_tenant(account) { … }` or `TenantKit.without_tenant { }`.
- **Unique constraints must include the tenant column** at the DB level: `add_index :projects, [:account_id, :slug], unique: true`. Pair it with `validates_uniqueness_to_tenant :slug`.
- **Lead composite indexes with the tenant column:** `add_index :projects, [:account_id, :status]`.

## 🧷 Why `default_scope`?

`default_scope` is rightly treated as an anti-pattern in ordinary application code: it applies to every query, leaks into associations and joins, and can seed attribute defaults on `.new`. So why does TenantKit use it?

Because tenancy is a **security boundary, not a convenience filter**, and the two options fail in opposite directions:

- **Explicit scoping fails *open*.** If a developer forgets to call the scope, the query silently returns *every* tenant's rows. The cost of a mistake is a cross-tenant data leak.
- **`default_scope` fails *closed*.** If a developer forgets, the query **raises `NoTenantSet`** instead of leaking. The cost of a mistake is a loud error in development, not a quiet breach in production.

For the thing being protected — one tenant seeing another's data — failing closed is the safer default. It's the same call [`acts_as_tenant`](https://github.com/ErwinM/acts_as_tenant) makes, for the same reason.

TenantKit also defuses the two edges that make `default_scope` painful:

- **No surprising `.new` defaults.** The tenant is assigned in a `before_validation`, *not* by the scope, and `.new` is wrapped so a built record never inherits scope values. `Project.new` behaves exactly as you'd expect.
- **No `unscoped` sledgehammer.** Instead of `unscoped` (which drops *every* condition on the model), you reach for `without_tenant { }`, which lifts only the tenant condition — explicit and greppable.

TenantKit also makes the tenant condition **merge-proof**: an association scope, `rewhere` or `unscope(where:)` on the tenant column adds to it instead of replacing it, so `other_account.projects` can't reach another tenant.

If you prefer opt-in scoping at the call site, use [explicit scoping mode](#-explicit-scoping-mode).

## 🤔 Why row-level (and not the others)?

| Strategy | Isolation | Ops cost | Verdict |
|---|:---:|:---:|:---:|
| **Row-level** (shared schema) | Good *(with discipline)* | 🟢 Low — one DB, one migration path | ✅ **Chosen** |
| Row-level + PostgreSQL RLS | Strong *(database-enforced)* | 🟢 Low — one policy migration | ✅ Optional |
| Schema-per-tenant | Strong | 🟠 High — migrations across N schemas, connection switching | ❌ Not supported |
| Database-per-tenant | Strongest | 🔴 Highest — provision + migrate N databases | ❌ Not supported |

Row-level works cleanly with every Rails default and has exactly **one** migration path. With strict scoping and database constraints it is safe enough for the overwhelming majority of B2B SaaS. See **[docs/COMPARISON.md](docs/COMPARISON.md)** for an honest comparison with acts_as_tenant, ros-apartment, activerecord-multi-tenant and Rails' built-ins — including when they are the better choice.

## 🏭 Used in production

TenantKit runs in production at [Uni-Grip](https://github.com/unigrip-inc), whose multi-brand platform scopes its brand-owned models with `belongs_to_tenant` in strict mode, with job propagation. Behaviour found there has fed back into the gem — for example, 0.2's change making `with_tenant` always scope when nested inside `without_tenant`.

Using TenantKit in production? A PR adding your name here is welcome.

## 📚 Documentation

| | |
|---|---|
| [docs/GUARANTEES.md](docs/GUARANTEES.md) | Every isolation guarantee, linked to its spec, plus what's your responsibility |
| [docs/POSTGRES_RLS.md](docs/POSTGRES_RLS.md) | Optional Row-Level Security: setup, strategies, PgBouncer, trade-offs |
| [docs/COMPARISON.md](docs/COMPARISON.md) | TenantKit vs acts_as_tenant, apartment, activerecord-multi-tenant, Rails built-ins |
| [docs/MIGRATING_FROM_ACTS_AS_TENANT.md](docs/MIGRATING_FROM_ACTS_AS_TENANT.md) | API mapping and step-by-step migration |
| [SECURITY.md](SECURITY.md) | Supported versions, private reporting, threat model |
| [CHANGELOG.md](CHANGELOG.md) | Releases and upgrade notes |
| [CONTRIBUTING.md](CONTRIBUTING.md) · [AGENTS.md](AGENTS.md) · [llms.txt](llms.txt) | Working on the gem (humans and AI assistants) |

## 🗺️ Roadmap

- [x] Optional explicit scoping mode *(0.2)*
- [x] Tenant-scoped Turbo Streams / Action Cable helpers *(0.2)*
- [x] Optional PostgreSQL Row-Level Security *(0.2)*
- [ ] Solid Cache / `Rails.cache` tenant-aware key helpers
- [ ] Plain Sidekiq (non-ActiveJob) middleware
- [ ] Schema-per-tenant / database-per-tenant modes

## 🛠️ Development

```bash
bundle install
bundle exec rspec                    # SQLite, newest Rails
DB=postgresql bundle exec rspec      # + the Row-Level Security specs
bin/matrix                           # Rails 7.2 / 8.0 / 8.1 x SQLite / PostgreSQL
bundle exec rubocop
```

CI runs Ruby 3.3 and 3.4 × Rails 7.2, 8.0 and 8.1 × SQLite, PostgreSQL and MySQL, with line coverage ≥ 90% enforced per job. See [CONTRIBUTING.md](CONTRIBUTING.md).

## 🤝 Contributing

Bug reports and pull requests are welcome at **[github.com/wintan1418/tenant_kit](https://github.com/wintan1418/tenant_kit)** — see [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md). Open an issue to discuss anything substantial before you build it.

**Found a cross-tenant leak?** Please report it privately — see [SECURITY.md](SECURITY.md).

## 📄 License

Released under the [MIT License](MIT-LICENSE).

<div align="center">

---

**[⬆ back to top](#-why-tenantkit)**

Built with ❤️ for Rails SaaS teams.

</div>
