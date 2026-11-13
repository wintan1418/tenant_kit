# TenantKit guarantees

This is the contract. Each guarantee links to the spec that proves it; the
suite runs in CI on Ruby 3.3 and 3.4 × Rails 7.2, 8.0 and 8.1 × SQLite,
PostgreSQL and MySQL. The adversarial specs live in [`spec/leaks/`](../spec/leaks):
they act as tenant A and try to reach tenant B.

Everything below applies to models declared with `belongs_to_tenant`, with the
default configuration (`require_tenant = true`, `prevent_cross_tenant_writes =
true`, `propagate_to_jobs = true`, `verify_job_arguments = true`), unless a row
says otherwise. If you find a way around any of these, it is a vulnerability —
please report it privately ([SECURITY.md](../SECURITY.md)).

## Reads

| Guarantee | Proven by |
|---|---|
| No current tenant (strict mode, the default): every read of an owned model raises `TenantKit::NoTenantSet` instead of returning rows. | [`reads_spec.rb:132`](../spec/leaks/reads_spec.rb#L132), [`strict_mode_spec.rb:13`](../spec/tenant_kit/strict_mode_spec.rb#L13), [`strict_mode_spec.rb:17`](../spec/tenant_kit/strict_mode_spec.rb#L17), [`strict_mode_spec.rb:21`](../spec/tenant_kit/strict_mode_spec.rb#L21) |
| `find`, `find_by`, `find_by!`, `find_sole_by` with another tenant's id raise `RecordNotFound` / return `nil`. | [`reads_spec.rb:10`](../spec/leaks/reads_spec.rb#L10), [`reads_spec.rb:14`](../spec/leaks/reads_spec.rb#L14), [`reads_spec.rb:18`](../spec/leaks/reads_spec.rb#L18) |
| `where`, `exists?`, `pluck`, `ids`, `pick`, `count`, `sum`, `maximum`, `group(...).count`, `first`/`last`/`take`, `find_each`, `in_batches` see only the current tenant. | [`reads_spec.rb:26`](../spec/leaks/reads_spec.rb#L26), [`reads_spec.rb:37`](../spec/leaks/reads_spec.rb#L37), [`reads_spec.rb:46`](../spec/leaks/reads_spec.rb#L46) |
| Conditions naming another tenant (`where(account_id: other)`, `where(account: other)`, SQL fragments) are added *alongside* the tenant condition and return nothing. | [`reads_spec.rb:54`](../spec/leaks/reads_spec.rb#L54) |
| `or` keeps the tenant condition on both sides. | [`reads_spec.rb:62`](../spec/leaks/reads_spec.rb#L62) |
| The tenant condition cannot be replaced or removed by `rewhere`, `unscope(where: :account_id)` or `merge` with a relation on the tenant column. | [`reads_spec.rb:71`](../spec/leaks/reads_spec.rb#L71), [`reads_spec.rb:75`](../spec/leaks/reads_spec.rb#L75), [`reads_spec.rb:79`](../spec/leaks/reads_spec.rb#L79) |
| `TenantKit.without_tenant` lifts only the tenant condition, and restores scoping afterwards even if the block raises. | [`reads_spec.rb:96`](../spec/leaks/reads_spec.rb#L96), [`reads_spec.rb:106`](../spec/leaks/reads_spec.rb#L106) |

## Associations, joins and preloading

| Guarantee | Proven by |
|---|---|
| A has_many reached from **another tenant's** tenant record (`other_account.projects`) is empty under the current tenant. *(0.1 returned the other tenant's rows.)* | [`associations_spec.rb:9`](../spec/leaks/associations_spec.rb#L9) |
| `joins`, `left_outer_joins`, `includes`, `preload`, `eager_load` apply the tenant condition to the joined / preloaded table. | [`associations_spec.rb:27`](../spec/leaks/associations_spec.rb#L27), [`associations_spec.rb:34`](../spec/leaks/associations_spec.rb#L34), [`associations_spec.rb:43`](../spec/leaks/associations_spec.rb#L43) |
| `has_many :through` is scoped on both the join and the target table, including from a global (non-tenant) model and nested through. | [`associations_spec.rb:52`](../spec/leaks/associations_spec.rb#L52), [`associations_spec.rb:59`](../spec/leaks/associations_spec.rb#L59), [`associations_spec.rb:66`](../spec/leaks/associations_spec.rb#L66) |
| A `belongs_to` (including polymorphic) pointing at another tenant's row loads `nil`, and a required one fails validation on create. | [`associations_spec.rb:72`](../spec/leaks/associations_spec.rb#L72), [`associations_spec.rb:77`](../spec/leaks/associations_spec.rb#L77), [`associations_spec.rb:87`](../spec/leaks/associations_spec.rb#L87), [`associations_spec.rb:94`](../spec/leaks/associations_spec.rb#L94) |
| Polymorphic `has_many as:` and STI subclasses inherit scoping, strict mode, auto-assignment and validation. | [`associations_spec.rb:102`](../spec/leaks/associations_spec.rb#L102), [`associations_spec.rb:108`](../spec/leaks/associations_spec.rb#L108), [`associations_spec.rb:116`](../spec/leaks/associations_spec.rb#L116), [`associations_spec.rb:120`](../spec/leaks/associations_spec.rb#L120) |

## Writes

| Guarantee | Proven by |
|---|---|
| Relation writes — `update_all`, `delete_all`, `destroy_all`, `delete_by`, `destroy_by`, `touch_all` — affect only the current tenant's rows. | [`writes_spec.rb:20`](../spec/leaks/writes_spec.rb#L20), [`writes_spec.rb:25`](../spec/leaks/writes_spec.rb#L25), [`writes_spec.rb:29`](../spec/leaks/writes_spec.rb#L29), [`writes_spec.rb:40`](../spec/leaks/writes_spec.rb#L40) |
| Class-level writes by id — `Model.update(id)`, `Model.destroy(id)`, `Model.delete(id)` — cannot reach another tenant's row. | [`writes_spec.rb:46`](../spec/leaks/writes_spec.rb#L46), [`writes_spec.rb:53`](../spec/leaks/writes_spec.rb#L53) |
| `update_counters`, `increment_counter`, `decrement_counter` are tenant-scoped (Rails runs them `unscoped`); with no tenant they raise in strict mode. | [`writes_spec.rb:58`](../spec/leaks/writes_spec.rb#L58), [`writes_spec.rb:67`](../spec/leaks/writes_spec.rb#L67), [`writes_spec.rb:72`](../spec/leaks/writes_spec.rb#L72) |
| `counter_cache` keeps working for the current tenant. | [`writes_spec.rb:78`](../spec/leaks/writes_spec.rb#L78) |
| `insert`, `insert_all`, `insert_all!`, `upsert`, `upsert_all`: rows without the tenant get the current tenant; rows naming another tenant raise `TenantKit::CrossTenantWrite`; with no tenant they raise `NoTenantSet` (strict); an upsert cannot overwrite another tenant's row through a shared unique key. | [`writes_spec.rb:85`](../spec/leaks/writes_spec.rb#L85), [`writes_spec.rb:90`](../spec/leaks/writes_spec.rb#L90), [`writes_spec.rb:102`](../spec/leaks/writes_spec.rb#L102), [`writes_spec.rb:107`](../spec/leaks/writes_spec.rb#L107), [`writes_spec.rb:115`](../spec/leaks/writes_spec.rb#L115), [`writes_spec.rb:119`](../spec/leaks/writes_spec.rb#L119) |
| Saving a record whose tenant is not the current tenant (e.g. a mass-assigned `account_id` from params) fails validation: *must be the current tenant*. | [`writes_spec.rb:126`](../spec/leaks/writes_spec.rb#L126), [`model_spec.rb:24`](../spec/tenant_kit/model_spec.rb#L24) |
| Changing the tenant of a persisted record fails validation (*cannot be changed to another tenant*); allowed only inside `without_tenant`. | [`writes_spec.rb:134`](../spec/leaks/writes_spec.rb#L134), [`writes_spec.rb:144`](../spec/leaks/writes_spec.rb#L144) |
| Nested attributes: children get the current tenant; a child naming another tenant is rejected; another tenant's child cannot be updated by id. | [`writes_spec.rb:194`](../spec/leaks/writes_spec.rb#L194), [`writes_spec.rb:201`](../spec/leaks/writes_spec.rb#L201), [`writes_spec.rb:209`](../spec/leaks/writes_spec.rb#L209) |
| Opt-in `config.scope_record_writes`: record-level `UPDATE`/`DELETE` (`save`, `update_columns`, `destroy`) also carry the tenant condition. | [`writes_spec.rb:175`](../spec/leaks/writes_spec.rb#L175), [`writes_spec.rb:185`](../spec/leaks/writes_spec.rb#L185) |
| `validates_uniqueness_to_tenant` scopes uniqueness to the tenant. | [`uniqueness_spec.rb:7`](../spec/tenant_kit/uniqueness_spec.rb#L7), [`uniqueness_spec.rb:12`](../spec/tenant_kit/uniqueness_spec.rb#L12) |

## Background jobs and mailers

| Guarantee | Proven by |
|---|---|
| A job runs under the tenant it was enqueued with — argument deserialization, callbacks and `perform` included — and the tenant is reset afterwards. | [`jobs_spec.rb:20`](../spec/leaks/jobs_spec.rb#L20), [`jobs_spec.rb:78`](../spec/leaks/jobs_spec.rb#L78) |
| A tenant-owned record argument (also inside arrays/hashes) that belongs to another tenant raises `TenantKit::TenantMismatch` before `perform` (opt out: `verify_job_arguments = false`). | [`jobs_spec.rb:26`](../spec/leaks/jobs_spec.rb#L26), [`jobs_spec.rb:33`](../spec/leaks/jobs_spec.rb#L33), [`jobs_spec.rb:39`](../spec/leaks/jobs_spec.rb#L39) |
| Retries (`retry_on`) keep the original tenant. | [`jobs_spec.rb:51`](../spec/leaks/jobs_spec.rb#L51), [`jobs_spec.rb:58`](../spec/leaks/jobs_spec.rb#L58) |
| `perform_now` inline uses the caller's tenant; `raise_on_missing_job_tenant` raises when there is none. | [`jobs_spec.rb:66`](../spec/leaks/jobs_spec.rb#L66), [`jobs_spec.rb:71`](../spec/leaks/jobs_spec.rb#L71) |
| Mailers sent with `deliver_later` render under the enqueuing tenant and reject another tenant's record argument. | [`jobs_spec.rb:92`](../spec/leaks/jobs_spec.rb#L92), [`jobs_spec.rb:102`](../spec/leaks/jobs_spec.rb#L102) |

## Execution state (threads, fibers, requests)

| Guarantee | Proven by |
|---|---|
| `with_tenant` always scopes, even nested inside `without_tenant`. *(0.1 stayed unscoped.)* | [`execution_state_spec.rb:9`](../spec/leaks/execution_state_spec.rb#L9) |
| Nested `with_tenant` restores the outer tenant, even on error; `with_tenant(nil)` is not an escape hatch. | [`execution_state_spec.rb:20`](../spec/leaks/execution_state_spec.rb#L20), [`execution_state_spec.rb:28`](../spec/leaks/execution_state_spec.rb#L28) |
| A new thread does not inherit the tenant (strict mode raises there); concurrent threads keep their own tenant. | [`execution_state_spec.rb:36`](../spec/leaks/execution_state_spec.rb#L36), [`execution_state_spec.rb:45`](../spec/leaks/execution_state_spec.rb#L45) |
| Fibers share the thread's tenant under the default `:thread` isolation level and get their own under `:fiber`. | [`execution_state_spec.rb:61`](../spec/leaks/execution_state_spec.rb#L61), [`execution_state_spec.rb:67`](../spec/leaks/execution_state_spec.rb#L67) |
| The Rails executor resets the tenant at the start and end of each unit of work (request, job); controllers reset it after each request. | [`execution_state_spec.rb:79`](../spec/leaks/execution_state_spec.rb#L79), [`execution_state_spec.rb:87`](../spec/leaks/execution_state_spec.rb#L87), [`controller_concern_spec.rb:26`](../spec/tenant_kit/controller_concern_spec.rb#L26) |

## Turbo Streams and Action Cable

| Guarantee | Proven by |
|---|---|
| Stream names built by TenantKit start with the tenant (same format as turbo-rails) and need a tenant. | [`streams_spec.rb:8`](../spec/tenant_kit/streams_spec.rb#L8), [`streams_spec.rb:16`](../spec/tenant_kit/streams_spec.rb#L16), [`streams_spec.rb:27`](../spec/tenant_kit/streams_spec.rb#L27), [`streams_spec.rb:31`](../spec/tenant_kit/streams_spec.rb#L31) |
| `broadcasts_to_tenant` broadcasts on the record's tenant stream and enqueues under the record's tenant, so the render is scoped even for records saved in `without_tenant`. | [`streams_spec.rb:48`](../spec/tenant_kit/streams_spec.rb#L48), [`streams_spec.rb:56`](../spec/tenant_kit/streams_spec.rb#L56), [`streams_spec.rb:83`](../spec/tenant_kit/streams_spec.rb#L83) |
| `TenantKit::Turbo::StreamsChannel` rejects signed stream names of other tenants and names without a tenant prefix. | [`cable_spec.rb:89`](../spec/tenant_kit/cable_spec.rb#L89), [`cable_spec.rb:95`](../spec/tenant_kit/cable_spec.rb#L95), [`cable_spec.rb:100`](../spec/tenant_kit/cable_spec.rb#L100) |
| `TenantKit::Cable` runs channel commands under the connection's tenant; `stream_for_tenant` / `reject_unless_current_tenant_owns` reject other tenants' records and connections without a tenant. | [`cable_spec.rb:10`](../spec/tenant_kit/cable_spec.rb#L10), [`cable_spec.rb:38`](../spec/tenant_kit/cable_spec.rb#L38), [`cable_spec.rb:45`](../spec/tenant_kit/cable_spec.rb#L45), [`cable_spec.rb:50`](../spec/tenant_kit/cable_spec.rb#L50), [`cable_spec.rb:70`](../spec/tenant_kit/cable_spec.rb#L70) |

## Explicit scoping mode (`belongs_to_tenant scoping: :explicit`)

| Guarantee | Proven by |
|---|---|
| `for_current_tenant` returns only the current tenant's rows; raises `NoTenantSet` with no tenant (strict) or returns nothing (non-strict). | [`explicit_scoping_spec.rb:22`](../spec/tenant_kit/explicit_scoping_spec.rb#L22), [`explicit_scoping_spec.rb:30`](../spec/tenant_kit/explicit_scoping_spec.rb#L30), [`explicit_scoping_spec.rb:34`](../spec/tenant_kit/explicit_scoping_spec.rb#L34) |
| Queries without `for_current_tenant` or a tenant-column condition raise `ExplicitScopeMissing` in development/test and log in other environments. | [`explicit_scoping_spec.rb:55`](../spec/tenant_kit/explicit_scoping_spec.rb#L55), [`explicit_scoping_spec.rb:83`](../spec/tenant_kit/explicit_scoping_spec.rb#L83), [`explicit_scoping_spec.rb:103`](../spec/tenant_kit/explicit_scoping_spec.rb#L103) |
| Write guards (auto-assign, cross-tenant validation, `insert_all`) apply in explicit mode too. | [`explicit_scoping_spec.rb:114`](../spec/tenant_kit/explicit_scoping_spec.rb#L114), [`explicit_scoping_spec.rb:122`](../spec/tenant_kit/explicit_scoping_spec.rb#L122) |

## PostgreSQL Row-Level Security (`config.postgres_rls = true`)

Run with `DB=postgresql`. See [POSTGRES_RLS.md](POSTGRES_RLS.md) for setup and
requirements (the app must connect as a role without `SUPERUSER`/`BYPASSRLS`).

| Guarantee | Proven by |
|---|---|
| Raw SQL, `find_by_sql`, `unscoped`, `select_all` return only the current tenant's rows. | [`rls_spec.rb:66`](../spec/postgres_rls/rls_spec.rb#L66), [`rls_spec.rb:71`](../spec/postgres_rls/rls_spec.rb#L71) |
| No tenant → no rows (fail closed). | [`rls_spec.rb:79`](../spec/postgres_rls/rls_spec.rb#L79) |
| Inserting, moving, updating or deleting another tenant's rows is refused by the database. | [`rls_spec.rb:93`](../spec/postgres_rls/rls_spec.rb#L93), [`rls_spec.rb:104`](../spec/postgres_rls/rls_spec.rb#L104), [`rls_spec.rb:113`](../spec/postgres_rls/rls_spec.rb#L113) |
| The setting is re-applied after savepoint rollbacks and reconnects, and per thread on a shared connection. | [`rls_spec.rb:123`](../spec/postgres_rls/rls_spec.rb#L123), [`rls_spec.rb:135`](../spec/postgres_rls/rls_spec.rb#L135), [`rls_spec.rb:189`](../spec/postgres_rls/rls_spec.rb#L189) |
| `:transaction` strategy works inside transactions and fails closed outside them; `:session` covers autocommit. | [`rls_spec.rb:144`](../spec/postgres_rls/rls_spec.rb#L144), [`rls_spec.rb:175`](../spec/postgres_rls/rls_spec.rb#L175), [`rls_spec.rb:180`](../spec/postgres_rls/rls_spec.rb#L180) |
| `without_tenant` bypasses via `tenant_kit.bypass` only while `postgres_rls_bypass` is on. | [`rls_spec.rb:84`](../spec/postgres_rls/rls_spec.rb#L84), [`rls_spec.rb:88`](../spec/postgres_rls/rls_spec.rb#L88) |

## Not guaranteed — your responsibility

These are deliberate escape hatches or outside what a row-level library can
see. Each "documented" behaviour is still pinned by a spec, so it can't change
silently.

| Path | What happens | Mitigation |
|---|---|---|
| **Resolving the tenant** for a request | TenantKit trusts whatever you assign to `current_tenant` | Authenticate first; verify the user belongs to the tenant before setting it. |
| `Model.unscoped` | Drops the tenant condition — [`reads_spec.rb:88`](../spec/leaks/reads_spec.rb#L88), [`reads_spec.rb:92`](../spec/leaks/reads_spec.rb#L92) | Use `without_tenant`; grep for `unscoped` in review; RLS. |
| `TenantKit.without_tenant` | Everything is unscoped and cross-tenant writes are allowed | Keep it to admin/seed/maintenance code; it's greppable on purpose. |
| Raw SQL: `find_by_sql`, `connection.select_all/execute`, `Arel.sql` | Not scoped — [`reads_spec.rb:115`](../spec/leaks/reads_spec.rb#L115), [`reads_spec.rb:119`](../spec/leaks/reads_spec.rb#L119) | Build SQL from scoped relations ([`reads_spec.rb:126`](../spec/leaks/reads_spec.rb#L126)), or enable RLS. |
| `update_column`, `update_columns`, and record-level writes on a record of another tenant you already hold | Skip validations and, by default, the tenant condition — [`writes_spec.rb:150`](../spec/leaks/writes_spec.rb#L150), [`writes_spec.rb:156`](../spec/leaks/writes_spec.rb#L156) | `config.scope_record_writes = true` ([`writes_spec.rb:175`](../spec/leaks/writes_spec.rb#L175)) or RLS. |
| `connection.raw_connection` | Bypasses TenantKit and the RLS sync | Don't use it for tenant data. |
| Models without `belongs_to_tenant` — including the tenant model itself, join tables you forgot, **Active Storage / Action Text tables** | Not scoped — [`active_storage_spec.rb:36`](../spec/leaks/active_storage_spec.rb#L36) | Reach attachments through their owner ([`active_storage_spec.rb:17`](../spec/leaks/active_storage_spec.rb#L17), [`active_storage_spec.rb:24`](../spec/leaks/active_storage_spec.rb#L24)); add `belongs_to_tenant` to every owned model. |
| Signed ids / GlobalIDs resolved outside a job (`ActiveStorage::Blob.find_signed`, `GlobalID::Locator.locate_signed`) | Located with `unscoped`, regardless of tenant — [`active_storage_spec.rb:43`](../spec/leaks/active_storage_spec.rb#L43) | Check ownership after locating; prefer `Model.find(id)` under the tenant. |
| A job enqueued with no tenant | Runs with no tenant (strict mode raises on owned-model queries) | `config.raise_on_missing_job_tenant = true`. |
| Plain Sidekiq (non-ActiveJob) workers, raw threads, `load_async` with an async executor | No tenant is propagated — [`execution_state_spec.rb:36`](../spec/leaks/execution_state_spec.rb#L36) | Pass the tenant id and use `with_tenant`. |
| Caches (`Rails.cache`, fragment caching) | Keys are not namespaced by tenant | Include the tenant in cache keys. |
| Database constraints | TenantKit doesn't create them | `NOT NULL` + foreign key on the tenant column; tenant-first unique indexes. Global unique indexes can reveal that a value exists in another tenant. |
| `config.require_tenant = false` | Owned-model queries with no tenant return **every** tenant's rows ([`strict_mode_spec.rb:40`](../spec/tenant_kit/strict_mode_spec.rb#L40)) | Keep strict mode on. |
| `config.prevent_cross_tenant_writes = false` | 0.1 behaviour: saves under another tenant are allowed ([`model_spec.rb:34`](../spec/tenant_kit/model_spec.rb#L34)) | Only as a temporary upgrade aid. |
| Action Cable / Turbo outside the helpers | Plain `stream_from`/`broadcasts_to` names are not tenant-prefixed | Use `stream_for_tenant`, `broadcasts_to_tenant`, `turbo_stream_from_tenant`. |
| SQL injection that executes arbitrary SQL as the app's database role | Can do anything that role can, including setting the RLS bypass | Fix the injection; for RLS, see the privileged-role option in POSTGRES_RLS.md. |
