# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/wintan1418/tenant_kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/wintan1418/tenant_kit/releases/tag/v0.1.0
