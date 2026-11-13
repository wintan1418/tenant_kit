# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-11-XX

Hardening release: an adversarial leak suite, fixes for the leaks it found,
write guards, explicit scoping mode, realtime helpers, optional PostgreSQL
Row-Level Security, and a CI matrix across Rails 7.2–8.1 and three databases.

### Upgrade notes

Read these before upgrading from 0.1. Each change makes TenantKit stricter;
the opt-outs exist only to ease migration.

- **`with_tenant` inside `without_tenant` now scopes.** In 0.1 the block kept
  scoping disabled, so it read as scoped but returned (and wrote) every tenant's
  rows. Code that relied on that should use `without_tenant` explicitly.
- **Cross-tenant saves are now validation errors** (`config.prevent_cross_tenant_writes`,
  default `true`): saving a record whose tenant is not the current tenant
  (*"must be the current tenant"*), and changing a persisted record's tenant
  (*"cannot be changed to another tenant"*). Both are allowed inside
  `without_tenant`. Set the option to `false` to restore 0.1 behaviour.
- **The tenant condition can no longer be replaced.** `other_account.projects`
  under a different current tenant, `rewhere(account_id: ...)` and
  `unscope(where: :account_id)` now return the current tenant's rows or nothing,
  instead of another tenant's rows. Use `without_tenant` for cross-tenant reads.
- **`insert_all` / `upsert_all` / `insert` / `upsert`** raise
  `TenantKit::CrossTenantWrite` for rows naming another tenant (0.1 silently
  rewrote them to the current tenant), and raise `NoTenantSet` with no tenant
  in strict mode.
- **`update_counters` / `increment_counter` / `decrement_counter`** are now
  tenant-scoped (and raise `NoTenantSet` with no tenant in strict mode).
- **Jobs:** the tenant is now set around `perform_now` rather than
  `around_perform`, so argument deserialization and every callback run under
  it. A tenant-owned record argument of another tenant raises
  `TenantKit::TenantMismatch` (`config.verify_job_arguments = false` to opt out).
- `require "tenant_kit"` now also requires `active_record`.

### Added

- Adversarial leak suite (`spec/leaks/`) covering finders, calculations,
  `rewhere`/`unscope`/`merge`, `unscoped`, raw SQL, joins and preloading,
  `has_many :through`, polymorphic and STI models, bulk and by-id writes,
  counters, `insert_all`/`upsert_all`, nested attributes, Active Storage,
  jobs, retries, mailers, threads, fibers and the Rails executor.
- `docs/GUARANTEES.md`: every guarantee linked to its spec, plus an explicit
  "your responsibility" list; a spec keeps the links accurate.
- Write guards: cross-tenant save/move validation, `insert_all`/`upsert_all`
  tenant filling and checks, tenant-scoped `update_counters`.
- `config.scope_record_writes` (opt-in): tenant condition on record-level
  `UPDATE`/`DELETE` via `default_scope all_queries: true`.
- Explicit scoping mode: `belongs_to_tenant scoping: :explicit`,
  `Model.for_current_tenant`, and `config.explicit_scoping_guard`
  (`:raise` in development/test, `:log` elsewhere) raising
  `TenantKit::ExplicitScopeMissing`.
- Turbo Streams / Action Cable: `TenantKit::Streams`, `broadcasts_to_tenant`
  (tenant-prefixed stream, enqueued under the record's tenant),
  `turbo_stream_from_tenant`, `tenant_stream_name`,
  `TenantKit::Turbo::StreamsChannel`, `TenantKit::Cable::Connection`
  (commands run under the connection's tenant) and `TenantKit::Cable::Channel`
  (`stream_for_tenant`, `broadcast_to_tenant`, `reject_unless_current_tenant_owns`).
- Optional PostgreSQL Row-Level Security: `config.postgres_rls`,
  `:session` / `:transaction` strategies (the latter for PgBouncer transaction
  pooling), `config.postgres_rls_bypass`, the `tenant_kit:rls` generator, and
  `docs/POSTGRES_RLS.md`.
- `TenantKit.current_tenant_id`, `TenantKit.current_tenant!`, `Model.tenant_owned?`.
- Errors: `TenantKit::CrossTenantWrite`, `TenantKit::TenantMismatch`,
  `TenantKit::ExplicitScopeMissing`.
- CI matrix: Ruby 3.3/3.4 × Rails 7.2/8.0/8.1 × SQLite/PostgreSQL/MySQL, with
  per-job coverage threshold (SimpleCov, ≥ 90% lines), RuboCop and gem build;
  `gemfiles/` and `bin/matrix` for local runs.
- Docs: SECURITY.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md, issue/PR templates,
  docs/COMPARISON.md, docs/MIGRATING_FROM_ACTS_AS_TENANT.md, llms.txt,
  AGENTS.md; gemspec `documentation_uri`.

### Changed

- The tenant condition is a `TenantKit::TenantPredicate` (an equality that
  Rails' same-column replacement cannot drop). SQL is unchanged.
- The install generator's initializer lists the new options.

### Security

- Fixed: a has_many reached from another tenant's tenant record
  (`Account.find(other_id).projects`) returned that tenant's rows, because
  Rails' association merge replaced the tenant condition.
- Fixed: `rewhere` / `unscope(where:)` / `merge` on the tenant column could
  remove the tenant condition.
- Fixed: `with_tenant` nested in `without_tenant` ran unscoped (found in
  production use).
- Fixed: `update_counters` and friends could modify another tenant's row by id.
- Fixed: a mass-assigned tenant foreign key could plant a record in another
  tenant; a persisted record could be moved to another tenant.
- Fixed: jobs could be handed (and act on) another tenant's record, since
  GlobalID locates arguments unscoped.

## [0.1.0] - 2026-07-01

Initial release: row-level (shared-schema) multi-tenancy for Rails.

### Added
- `belongs_to_tenant` macro: declares the tenant association, scopes all reads
  to the current tenant via `default_scope`, auto-assigns the tenant on create
  through `before_validation`, and validates tenant presence.
- `TenantKit::Current` (`ActiveSupport::CurrentAttributes`) as the request-scoped
  holder of the current tenant.
- `TenantKit.with_tenant` / `TenantKit.without_tenant` scoping controls.
- Strict mode (`config.require_tenant`, on by default): querying a tenant-scoped
  model with no current tenant raises `TenantKit::NoTenantSet`.
- `validates_uniqueness_to_tenant`: uniqueness scoped to the tenant column.
- Controller resolution helpers: `set_current_tenant_by_subdomain`,
  `set_current_tenant_by_domain`, `set_current_tenant_by_header`, and
  `set_current_tenant_through_filter`.
- Background-job tenant propagation (`config.propagate_to_jobs`): the tenant's
  GlobalID is captured at enqueue and re-established around `perform`, surviving
  ActiveJob serialization (Solid Queue included).
- Generators: `tenant_kit:install` and `tenant_kit:migration`.

[Unreleased]: https://github.com/wintan1418/tenant_kit/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/wintan1418/tenant_kit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/wintan1418/tenant_kit/releases/tag/v0.1.0
