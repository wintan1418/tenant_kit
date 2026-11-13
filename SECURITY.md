# Security Policy

TenantKit sits on a security boundary — one tenant must never see or change
another tenant's data — so we treat isolation bugs as security vulnerabilities.

## Supported versions

| Version | Supported |
|---|---|
| 0.2.x | ✅ security fixes |
| 0.1.x | ❌ — upgrade to 0.2 (see the upgrade notes in [CHANGELOG.md](CHANGELOG.md)) |
| < 0.1 | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's security advisories:
**[Report a vulnerability](https://github.com/wintan1418/tenant_kit/security/advisories/new)**
(repository → *Security* → *Report a vulnerability*).

Include what you can of:

- the TenantKit, Rails, Ruby and database versions;
- the model setup and the code path that crosses the tenant boundary;
- a minimal reproduction — ideally a failing spec in the style of `spec/leaks/`.

TenantKit is maintained by one person, so these are targets, not guarantees:

- acknowledgement within **3 working days**;
- an assessment (confirmed / not a vulnerability / needs more information)
  within **10 working days**;
- for confirmed issues, a fix and a coordinated release, normally within
  **30 days** — faster for actively exploitable leaks;
- credit in the advisory and CHANGELOG, if you want it.

## Disclosure

We follow coordinated disclosure. Once a fix is released we publish a GitHub
Security Advisory (and request a CVE where appropriate) describing affected
versions, impact and the upgrade path. Please give us a reasonable window
(default 90 days from the report) before disclosing publicly; we'll agree on an
earlier date if a fix ships sooner.

## Threat model

**In scope — TenantKit is meant to prevent these:**

- Reading another tenant's rows through Active Record query APIs on models
  declared with `belongs_to_tenant` (finders, relations, calculations,
  associations, joins, preloading, STI, polymorphic targets).
- Writing into another tenant through Active Record write APIs: relation
  `update_all` / `delete_all` / `destroy_all`, class-level writes by id,
  counter updates, `insert_all` / `upsert_all`, saving a record with another
  tenant's foreign key, moving a record to another tenant.
- Silent unscoped access because no tenant is set (strict mode raises
  `NoTenantSet`).
- Background jobs and mailers running under the wrong tenant, or being handed
  another tenant's record.
- Tenant state leaking between requests or jobs on a reused thread.
- With Turbo / Action Cable helpers: broadcasts reaching, or subscriptions
  being accepted for, another tenant's stream.
- With optional PostgreSQL RLS: any SQL on an RLS table, including raw SQL, run
  by the application role while a different (or no) tenant is current.

A failure of any of these is a vulnerability — please report it.

**Out of scope — the application's responsibility** (documented in
[docs/GUARANTEES.md](docs/GUARANTEES.md#not-guaranteed--your-responsibility)):

- Deciding *which* tenant a request belongs to (authentication, resolving the
  tenant from a subdomain or header, verifying the user is a member).
- Explicit escape hatches: `Model.unscoped`, `TenantKit.without_tenant`,
  raw SQL (unless RLS is enabled), `update_column(s)` (unless
  `scope_record_writes` or RLS), `connection.raw_connection`.
- Tables of models that don't call `belongs_to_tenant`, including Active
  Storage / Action Text tables and caches.
- Records loaded by GlobalID / signed GlobalID outside a job (GlobalID locates
  with `unscoped`).
- Attackers who can execute arbitrary SQL as the application's database role.
- Denial of service, timing side channels, and global unique constraints that
  reveal a value exists in some tenant.

## Hardening checklist

- Keep `config.require_tenant = true` and `config.prevent_cross_tenant_writes = true` (defaults).
- Put the tenant column first in composite and unique indexes; make it `NOT NULL` with a foreign key.
- Grep for `unscoped`, `without_tenant`, `find_by_sql`, `update_column` in review.
- Consider `config.scope_record_writes = true` and PostgreSQL RLS
  ([docs/POSTGRES_RLS.md](docs/POSTGRES_RLS.md)) for defence in depth.
