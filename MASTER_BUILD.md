# TenantKit — Master Build Document

> A row-level (shared-schema) multi-tenancy gem for Rails 8, built on
> `ActiveSupport::CurrentAttributes`, with first-class background-job tenant
> propagation. This document is the single source of truth for the build.

**Working gem name:** `tenant_kit` (module `TenantKit`)
**Status of this document:** Locked spec. No speculative features. Everything
here is a proven pattern.

> **Rename before publishing.** Check `https://rubygems.org/gems/tenant_kit`
> for name availability first. If taken, pick another and find-replace the
> module/name throughout. All internal design is name-agnostic.

---

## 1. What this gem does (in one paragraph)

TenantKit makes a Rails app multi-tenant using the **row-level / shared-schema**
strategy: one database, one shared schema, and a `tenant_id` foreign key on
every tenant-owned table. It tracks a "current tenant" per request, automatically
scopes all queries to that tenant, auto-assigns the tenant on new records, and —
critically — carries the current tenant into background jobs (Solid Queue /
ActiveJob) so async work never leaks across tenants. It is strict by default:
querying a tenant-scoped model with no tenant set raises, instead of silently
returning another tenant's data.

---

## 2. Why this strategy (and why NOT the others)

This is a deliberate decision, not a default we fell into.

| Strategy | Isolation | Ops cost | Verdict |
|---|---|---|---|
| **Row-level (shared schema)** — `tenant_id` column, app-level scoping | Good (with discipline) | Low — one DB, one migration path | **CHOSEN** |
| Schema-per-tenant (Postgres schemas, à la `apartment`) | Strong | High — migrations run across N schemas, connection switching, backups + Solid Queue get painful | Rejected |
| Database-per-tenant (multi-db / sharding) | Strongest | Highest — provision + migrate N databases, heavy tooling | Rejected for v1; a later scaling-stage decision |

**Why row-level wins for this gem:** it works cleanly with every Rails 8 default
(Solid Queue, Solid Cache, Solid Cable, standard migrations, connection pooling),
it has exactly one migration path, and with strict scoping + database
constraints it is safe enough for the overwhelming majority of B2B SaaS. The
other two are legitimate at large scale but are the wrong place to start.

---

## 3. Non-negotiable design rules

These are the rules that separate a correct implementation from a leaky one.
Claude Code MUST follow all of them.

1. **Use `ActiveSupport::CurrentAttributes`, never `Thread.current` directly.**
   Current-tenant state lives in `TenantKit::Current`. It is request-scoped and
   auto-resets between requests, which prevents state bleeding across requests
   on a reused thread.
2. **Auto-assign tenant via `before_validation`, not via `default_scope` create
   behavior.** Relying on `default_scope` to set attributes on create is a known
   foot-gun; assign explicitly.
3. **Strict by default.** If `require_tenant` is true (the default) and a
   tenant-scoped model is queried with no current tenant and not inside a
   `without_tenant` block, raise `TenantKit::NoTenantSet`. Silent unscoped
   queries are a data-leak, not a convenience.
4. **Every unique constraint on a tenant-owned table must include `tenant_id`**
   — both at the database level (unique index) and in model validations
   (`validates_uniqueness_to_tenant`).
5. **Background jobs must re-establish the tenant.** A job enqueued under tenant
   A must run under tenant A even though it executes in a different
   process/thread with no request context.
6. **No runtime dependencies beyond Rails.** The gem depends only on
   `activerecord`, `activesupport`, `railties` (and `actionpack`/`activejob`
   through Rails). No `rest-client`, no HTTP libs, nothing exotic.
7. **Provide explicit escape hatches, and make them loud.**
   `TenantKit.without_tenant { }` and `TenantKit.with_tenant(t) { }` are the only
   sanctioned ways to step outside the current tenant. Document that they exist
   for admin tools, seeds, migrations, and the console.

---

## 4. Public API surface (the contract)

This is what a host application sees after installing the gem.

### 4.1 Declaring a tenant-owned model

```ruby
class Project < ApplicationRecord
  belongs_to_tenant   # assumes an `account_id` / tenant column per config
end

# With an explicit association:
class Invoice < ApplicationRecord
  belongs_to_tenant :account, class_name: "Account", foreign_key: "account_id"
end
```

`belongs_to_tenant` does all of the following:
- declares `belongs_to :account` (name/class/fk configurable)
- adds a `default_scope` that filters by the current tenant
- adds a `before_validation` that assigns the current tenant to new records
- validates presence of the tenant association
- exposes `validates_uniqueness_to_tenant(*attrs, **opts)`

### 4.2 The current tenant

```ruby
TenantKit::Current.tenant            # => #<Account ...> or nil
TenantKit::Current.tenant = account  # set manually (rarely needed directly)

TenantKit.with_tenant(account) do
  # everything in here is scoped to `account`
end

TenantKit.without_tenant do
  # scoping is disabled in here (admin / seeds / migrations / console)
end
```

### 4.3 Controller resolution helpers (via `TenantKit::ControllerConcern`)

Auto-included into `ActionController::Base` and `ActionController::API`.

```ruby
class ApplicationController < ActionController::Base
  set_current_tenant_by_subdomain(:account, :subdomain)   # tenant.subdomain == request.subdomain
  # or
  set_current_tenant_by_domain(:account, :domain)         # tenant.domain == request.host
  # or
  set_current_tenant_by_header("X-Tenant-Id")             # for APIs
  # or, fully custom:
  set_current_tenant_through_filter
  before_action :find_tenant
  def find_tenant
    self.current_tenant = Account.find_by!(slug: params[:account_slug])
  end
end
```

Each helper installs a `before_action` that resolves and sets
`TenantKit::Current.tenant` for the request. `CurrentAttributes` handles reset.

### 4.4 Configuration (`config/initializers/tenant_kit.rb`)

```ruby
TenantKit.configure do |config|
  config.tenant_class          = "Account"   # the model that represents a tenant
  config.tenant_column         = "account_id"# FK column on owned tables
  config.require_tenant        = true        # strict mode (raise when unscoped)
  config.propagate_to_jobs     = true        # carry tenant into ActiveJob
  config.raise_on_missing_job_tenant = false # if a job was enqueued with no tenant
end
```

### 4.5 Generators

```bash
rails g tenant_kit:install
#  -> config/initializers/tenant_kit.rb
#  -> (optionally) the Account model + migration if it doesn't exist
#  -> post-install notes

rails g tenant_kit:migration Project
#  -> a migration adding: add_reference :projects, :account,
#         null: false, foreign_key: true, index: true
```

---

## 5. Internal architecture — file by file

Target layout (generated first by `rails plugin new tenant_kit --dummy-path=spec/dummy -T`):

```
tenant_kit/
├── tenant_kit.gemspec
├── Gemfile
├── Rakefile
├── README.md
├── CHANGELOG.md
├── lib/
│   ├── tenant_kit.rb                      # entrypoint: requires + configure
│   ├── tenant_kit/
│   │   ├── version.rb
│   │   ├── configuration.rb               # the config object
│   │   ├── current.rb                     # ActiveSupport::CurrentAttributes
│   │   ├── errors.rb                      # NoTenantSet, etc.
│   │   ├── model.rb                       # belongs_to_tenant macro + scoping
│   │   ├── uniqueness_validator.rb        # validates_uniqueness_to_tenant
│   │   ├── controller_concern.rb          # resolution helpers
│   │   ├── job.rb                         # ActiveJob tenant propagation
│   │   ├── railtie.rb                     # wires into Rails on boot
│   │   └── testing.rb                     # RSpec/Minitest helpers (opt-in)
│   └── generators/
│       └── tenant_kit/
│           ├── install/
│           │   ├── install_generator.rb
│           │   └── templates/
│           │       ├── initializer.rb.tt
│           │       └── account_migration.rb.tt
│           └── migration/
│               ├── migration_generator.rb
│               └── templates/
│                   └── add_tenant_reference.rb.tt
└── spec/
    ├── spec_helper.rb
    ├── rails_helper.rb
    ├── dummy/                             # the throwaway host app for testing
    │   └── ... (Account + Project models, DB config)
    └── tenant_kit/
        ├── model_spec.rb
        ├── scoping_spec.rb
        ├── uniqueness_spec.rb
        ├── strict_mode_spec.rb
        ├── controller_concern_spec.rb
        ├── job_propagation_spec.rb
        └── configuration_spec.rb
```

### 5.1 `TenantKit::Current`

```ruby
module TenantKit
  class Current < ActiveSupport::CurrentAttributes
    attribute :tenant
    # internal flag used by without_tenant to disable scoping
    attribute :scoping_disabled
  end
end
```

### 5.2 `TenantKit::Model` (the heart)

```ruby
module TenantKit
  module Model
    extend ActiveSupport::Concern

    class_methods do
      def belongs_to_tenant(association = nil, **options)
        assoc = association || TenantKit.config.tenant_class.underscore.to_sym
        fk    = options[:foreign_key] || TenantKit.config.tenant_column

        belongs_to assoc, **options.slice(:class_name, :foreign_key, :optional)

        # Scope every query to the current tenant.
        default_scope do
          if TenantKit.scoping_active?
            where(fk => TenantKit::Current.tenant.public_send(:id))
          elsif TenantKit.config.require_tenant && !TenantKit.scoping_disabled?
            raise TenantKit::NoTenantSet, "No current tenant set for #{name}"
          else
            all
          end
        end

        # Assign tenant on create.
        before_validation do
          if TenantKit::Current.tenant && public_send(assoc).nil?
            public_send("#{assoc}=", TenantKit::Current.tenant)
          end
        end

        validates assoc, presence: true, unless: -> { TenantKit.scoping_disabled? }

        define_singleton_method(:validates_uniqueness_to_tenant) do |*attrs, **opts|
          validates_each(attrs) do |record, attr, value|
            # delegate to a scoped uniqueness check keyed on tenant_column
          end
        end
      end
    end
  end
end
```

> **Note for the implementer:** the `default_scope` block above is written for
> clarity. Implement `TenantKit.scoping_active?` (tenant present AND not
> disabled) and `TenantKit.scoping_disabled?` on the `TenantKit` module reading
> `Current`. Verify behavior against `unscoped`, associations, and
> `find_or_create_by` in the test suite. `default_scope` has known sharp edges;
> the tests exist to pin them down.

### 5.3 Scoping control (`lib/tenant_kit.rb` module methods)

```ruby
module TenantKit
  def self.with_tenant(tenant)
    previous = Current.tenant
    Current.tenant = tenant
    yield
  ensure
    Current.tenant = previous
  end

  def self.without_tenant
    was = Current.scoping_disabled
    Current.scoping_disabled = true
    yield
  ensure
    Current.scoping_disabled = was
  end

  def self.scoping_active?
    Current.tenant.present? && !Current.scoping_disabled
  end

  def self.scoping_disabled?
    !!Current.scoping_disabled
  end
end
```

### 5.4 `TenantKit::Job` — background propagation (the differentiator)

The problem: a job runs later, in another process, with no `Current.tenant`.
The fix: capture the tenant's global identity at enqueue time, serialize it into
the job, and re-establish it around `perform`.

```ruby
module TenantKit
  module Job
    extend ActiveSupport::Concern

    included do
      # capture at enqueue
      around_enqueue do |job, block|
        job.tenant_kit_gid ||= TenantKit::Current.tenant&.to_global_id&.to_s
        block.call
      end

      # restore at perform
      around_perform do |job, block|
        if job.tenant_kit_gid
          tenant = GlobalID::Locator.locate(job.tenant_kit_gid)
          TenantKit.with_tenant(tenant) { block.call }
        elsif TenantKit.config.raise_on_missing_job_tenant
          raise TenantKit::NoTenantSet, "Job #{job.class} enqueued without a tenant"
        else
          block.call
        end
      end
    end

    included { attr_accessor :tenant_kit_gid }
    # ensure tenant_kit_gid survives serialization: override serialize/deserialize
    # OR store it in job arguments metadata. Pin this in job_propagation_spec.rb.
  end
end
```

> **Implementer note:** GlobalID is already available in Rails. Confirm the
> `tenant_kit_gid` round-trips through Solid Queue's serialization (it uses
> ActiveJob's `serialize`/`deserialize`). Test with an actual enqueue →
> `perform_enqueued_jobs` cycle in `job_propagation_spec.rb`, asserting the
> tenant is correct inside the job and reset afterward.

### 5.5 `TenantKit::Railtie`

```ruby
module TenantKit
  class Railtie < ::Rails::Railtie
    initializer "tenant_kit.active_record" do
      ActiveSupport.on_load(:active_record) { include TenantKit::Model }
    end

    initializer "tenant_kit.action_controller" do
      ActiveSupport.on_load(:action_controller_base) { include TenantKit::ControllerConcern }
      ActiveSupport.on_load(:action_controller_api)  { include TenantKit::ControllerConcern }
    end

    initializer "tenant_kit.active_job" do
      ActiveSupport.on_load(:active_job) do
        include TenantKit::Job if TenantKit.config.propagate_to_jobs
      end
    end
  end
end
```

---

## 6. Data model & migration conventions

- The tenant table (default `accounts`) is a normal model — it does NOT call
  `belongs_to_tenant`.
- Every tenant-owned table gets: `t.references :account, null: false, foreign_key: true`.
- Indexes must **lead with the tenant column**: a query filtered by
  `account_id` plus another column wants `add_index :projects, [:account_id, :status]`.
- Unique constraints must include the tenant column:
  `add_index :projects, [:account_id, :slug], unique: true`.
- Prefer `null: false` on `account_id` for every owned table. Records with no
  tenant are a bug, and the DB should say so.

---

## 7. Security posture (why this is safe enough)

1. **Strict mode** raises on unscoped tenant queries — no silent cross-tenant reads.
2. **DB-level FK + NOT NULL** on every `account_id`.
3. **Unique indexes include the tenant column** — no cross-tenant uniqueness collisions or leaks.
4. **Job propagation** closes the most common real-world leak (async work).
5. **Loud, auditable escape hatch** — `without_tenant` is the only way out and is easy to grep for in review.
6. **Action Cable / Turbo Streams guidance (documented, not enforced):** stream
   names for tenant data must include the tenant identifier
   (`stream_for [current_tenant, record]`) so broadcasts never fan out across
   tenants. Add this to the README's "Gotchas" section.

---

## 8. Testing plan (definition of done)

All tests run against `spec/dummy`, which defines `Account` (tenant) and
`Project` / `Invoice` (owned) models. Use RSpec + transactional fixtures.

Required test coverage:

- **scoping_spec**: with tenant set, `Project.all` returns only that tenant's rows; switching tenants switches results; `with_tenant` scopes correctly and restores.
- **model_spec**: `belongs_to_tenant` sets up the association; new records auto-assign the current tenant; presence validation fires without a tenant (outside `without_tenant`).
- **uniqueness_spec**: `validates_uniqueness_to_tenant` allows the same value across different tenants and blocks duplicates within one tenant.
- **strict_mode_spec**: with `require_tenant = true` and no tenant, a query raises `TenantKit::NoTenantSet`; inside `without_tenant`, the same query succeeds and returns all rows.
- **controller_concern_spec**: subdomain, domain, and header resolvers each set the correct tenant; tenant resets between requests.
- **job_propagation_spec**: a job enqueued under tenant A performs under tenant A; the tenant is reset after; a job enqueued with no tenant behaves per `raise_on_missing_job_tenant`.
- **configuration_spec**: config defaults are correct; overrides take effect.

**Done means:** all specs green, no `Thread.current` in the codebase, zero
runtime deps beyond Rails, README complete with the Gotchas section, and the
`install` + `migration` generators produce working files in a fresh dummy app.

---

## 9. Build order (milestones for Claude Code)

Build in this order. Each milestone must be green before the next.

1. **Skeleton** — `rails plugin new tenant_kit --dummy-path=spec/dummy -T`, add RSpec, gemspec metadata, `version.rb`, `configuration.rb`, `current.rb`, `errors.rb`, `railtie.rb` (empty hooks). Dummy app boots.
2. **Model core** — `belongs_to_tenant`, `default_scope`, `before_validation` auto-assign, presence validation, `with_tenant` / `without_tenant`. Pass `scoping_spec`, `model_spec`.
3. **Uniqueness + strict mode** — `validates_uniqueness_to_tenant`, `NoTenantSet` behavior. Pass `uniqueness_spec`, `strict_mode_spec`.
4. **Controller resolution** — the `set_current_tenant_by_*` helpers. Pass `controller_concern_spec`.
5. **Job propagation** — `TenantKit::Job`, GlobalID round-trip. Pass `job_propagation_spec`.
6. **Generators** — `install` + `migration`. Verify by running them into the dummy app.
7. **Docs + polish** — README (usage, config, gotchas), CHANGELOG, YARD comments on public methods, `standardrb`/`rubocop` clean.

---

## 10. Versions & toolchain

- **Ruby:** `>= 3.3` (3.1 is EOL; 3.2 reaches EOL in 2026 — target 3.3+).
- **Rails:** `>= 7.2`, primary target `8.x`.
- **Test:** RSpec.
- **Lint:** `standardrb` (or RuboCop rails/omakase — pick one, stay consistent).
- **Docs:** YARD comments on every public method.
- **Runtime deps:** `railties`, `activerecord`, `activesupport` only.

## 11. Explicitly out of scope for v1

To keep this shippable, these are NOT in the first version (note them in the
README roadmap, do not build them):
- Schema-per-tenant or database-per-tenant modes.
- Automatic Action Cable stream scoping (documented guidance only).
- Tenant-aware caching helpers for Solid Cache.
- Admin UI / dashboard.

Ship the row-level core, correct and well-tested, first.
