# How TenantKit compares

An honest comparison with the other common ways to do multi-tenancy in Rails,
including where the alternatives are the better choice. Facts about other
projects are taken from their READMEs as of November 2026 — check them for
current details, and please open a PR if something here is out of date or
unfair.

## At a glance

| | **TenantKit** | **acts_as_tenant** | **ros-apartment** | **activerecord-multi-tenant** | **Rails built-ins** |
|---|---|---|---|---|---|
| Strategy | row-level (shared schema) | row-level | schema-per-tenant (PG) / db-per-tenant | row-level, built for Citus | db-per-tenant via horizontal sharding (`connected_to(shard:)`) |
| Isolation enforced by | Active Record, + optional PostgreSQL RLS | Active Record | the database (separate schemas / databases) | Active Record (+ Citus routing) | the database (separate databases) |
| Age / adoption | young (first release July 2026) | mature (since 2011), widely used | mature (fork of influitive/apartment) | mature, Citus-backed | part of Rails |
| Rails support | 7.2, 8.0, 8.1 (CI-tested) | see its README | 8.1+ for v4 | README lists 6.0–7.0 | — |
| Strict "no tenant → raise" | ✅ default | ✅ `require_tenant` (bool or lambda) | ✅ `require_tenant!` | ❌ | n/a |
| Tenant condition can't be replaced by association / `rewhere` / `unscope(where:)` | ✅ ([spec](../spec/leaks/reads_spec.rb)) | — (not documented) | n/a | — | n/a |
| Cross-tenant save rejected | ✅ validation | ✅ validation | n/a | — | n/a |
| Changing a record's tenant | only inside `without_tenant` | only inside `with_mutable_tenant` | n/a | — | n/a |
| `insert_all` / `upsert_all` | tenant filled; rows for other tenants raise | not guarded (documented) | n/a | — | n/a |
| `update_counters` by id | tenant-scoped | not scoped (documented) | n/a | — | n/a |
| Record-level writes scoped (`update_columns`, `destroy`) | opt-in (`scope_record_writes`) | ❌ | ✅ (schema) | — | ✅ (database) |
| Raw SQL protected | opt-in PostgreSQL RLS | ❌ | ✅ | ❌ | ✅ |
| ActiveJob propagation | ✅ GlobalID in payload, set around `perform_now`, foreign record arguments rejected | ✅ | manual switching | not documented | manual |
| Sidekiq-native (non-ActiveJob) jobs | ❌ (ActiveJob only) | ✅ middleware | manual | — | manual |
| Turbo Streams / Action Cable helpers | ✅ tenant-prefixed streams, subscription verification | documents Action Cable `around_command` | — | — | — |
| Explicit (no `default_scope`) mode | ✅ opt-in, with dev/test guard | ❌ | n/a | ✅ write-only mode for rollouts | n/a |
| Tenant through a join table (`through:`) / polymorphic tenant | ❌ | ✅ | n/a | — | n/a |
| Migrations | one path | one path | across N schemas / databases | one path | across N databases |
| Published leak test suite + guarantees doc | ✅ [GUARANTEES.md](GUARANTEES.md) | — | — | — | — |

"n/a" = not applicable to that strategy; "—" = not covered by its README (it may still behave well — we simply haven't verified it).

## When to pick something else

**acts_as_tenant** — if you want the most battle-tested row-level gem. It has
years of production use across many apps, a bigger community, Sidekiq
middleware for plain Sidekiq workers, a lambda `require_tenant`, tenants
reached `through:` a join model, polymorphic tenants, and a test middleware for
request specs. TenantKit's design is close to it (same `default_scope`
approach, similar API — see
[MIGRATING_FROM_ACTS_AS_TENANT.md](MIGRATING_FROM_ACTS_AS_TENANT.md)), and its
advantages are narrower: the merge-proof tenant predicate, guarded
`insert_all` / `update_counters`, job argument verification, stream helpers,
explicit mode, optional RLS, and a published leak suite. Maturity is a real
factor for a security boundary; weigh it.

**ros-apartment / schema- or database-per-tenant** — if tenants need hard
isolation for compliance or contractual reasons, per-tenant backup/restore, or
per-tenant data residency. Separation by schema or database protects raw SQL
and forgotten scopes by construction. The costs are operational: migrations run
N times, connection handling is more complex (its README warns that schema mode
behind PgBouncer transaction pooling can return another tenant's data unless
PostgreSQL 18+ is configured for it), and cross-tenant reporting is harder.

**activerecord-multi-tenant** — if you run, or plan to run, Citus to shard
tenants across nodes. It's built so the distributed database can route queries
by tenant.

**Rails horizontal sharding** — if you want database-per-tenant without a gem
and can manage connection switching yourself (`connects_to shards:` /
`connected_to(shard:)`).

## When TenantKit fits

- One shared database is what you want to operate (one migration path, Solid
  Queue / Cache / Cable, ordinary pooling).
- You want strict, fail-closed defaults and guards for the less obvious write
  paths, and you'd like the option of PostgreSQL RLS underneath without
  changing the application model.
- You use ActiveJob, Turbo Streams or Action Cable and want tenant handling
  there by construction.
- You are comfortable adopting a young library: read
  [GUARANTEES.md](GUARANTEES.md), run the leak suite, and pin versions.
