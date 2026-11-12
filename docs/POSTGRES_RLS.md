# PostgreSQL Row-Level Security (optional)

TenantKit's normal protection lives in Active Record: a strict tenant condition
on every query of a tenant-owned model. That protects everything that goes
through Active Record's query builder. It cannot protect SQL that doesn't —
`find_by_sql`, `connection.select_all`, `Model.unscoped`, `update_columns` on a
record loaded elsewhere, a reporting query someone writes by hand next year.

With `config.postgres_rls = true`, PostgreSQL itself enforces the boundary as a
second line of defence: each tenant table gets a [row-level security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
policy, and TenantKit tells the database which tenant is current.

It is **off by default** and PostgreSQL-only.

## What you get

Proven against a real PostgreSQL in [`spec/postgres_rls/rls_spec.rb`](../spec/postgres_rls/rls_spec.rb)
(run with `DB=postgresql`):

| With RLS enabled, acting as tenant A | Result |
|---|---|
| `connection.select_values("SELECT name FROM projects")` | only A's rows |
| `Project.find_by_sql(...)`, `Project.unscoped.count` | only A's rows |
| any query with **no** tenant set | no rows (fail closed) |
| `INSERT` / `UPDATE ... SET account_id = B` via raw SQL | error: `new row violates row-level security policy` |
| `UPDATE` / `DELETE` of B's rows via `unscoped`, `update_columns` | 0 rows affected |
| `TenantKit.without_tenant { ... }` | every row (via the bypass setting), or none if you disable the bypass |

## Setup

1. **Generate the policy migration.**

   ```bash
   rails g tenant_kit:rls                 # every model that calls belongs_to_tenant
   rails g tenant_kit:rls Project Invoice # or just these
   rails g tenant_kit:rls --column-type=uuid --no-bypass
   ```

   For each table the migration runs (plain SQL — it does not depend on
   TenantKit at migrate time):

   ```sql
   ALTER TABLE "projects" ENABLE ROW LEVEL SECURITY;
   ALTER TABLE "projects" FORCE ROW LEVEL SECURITY;
   CREATE POLICY tenant_kit_isolation ON "projects" AS PERMISSIVE FOR ALL
     USING (("account_id" = NULLIF(current_setting('tenant_kit.tenant_id', true), '')::bigint)
            OR current_setting('tenant_kit.bypass', true) = 'on')
     WITH CHECK (<same condition>);
   ```

   `current_setting(..., true)` returns `NULL` when the setting is missing, so a
   connection that never set a tenant sees nothing. The comparison is on the
   column's own type, so the tenant index is still used.

2. **Turn it on** in `config/initializers/tenant_kit.rb`:

   ```ruby
   config.postgres_rls = true
   # config.postgres_rls_strategy = :transaction  # behind PgBouncer transaction pooling (see below)
   ```

3. **Connect as an ordinary role.** PostgreSQL never applies policies to
   superusers or roles with `BYPASSRLS`. Many setups (local development, some
   managed databases' default user) connect as a superuser — RLS is silently a
   no-op there. Create an application role:

   ```sql
   CREATE ROLE app_user LOGIN PASSWORD '...' NOSUPERUSER NOBYPASSRLS;
   GRANT USAGE ON SCHEMA public TO app_user;
   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
   GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
   ```

   Run migrations as the owner role and the app as `app_user`. The migration
   uses `FORCE ROW LEVEL SECURITY` so the policy also applies to the table owner
   (otherwise owners are exempt).

4. **Check it's live:** as the app role, with no tenant set,
   `SELECT count(*) FROM projects` must return `0`.

## How TenantKit sets the tenant

TenantKit prepends a small hook to Active Record's PostgreSQL adapter, inside
`with_raw_connection` — the method every statement goes through in Rails 7.2,
8.0 and 8.1. Right before a statement runs, TenantKit compares what the code
issuing it expects (`TenantKit::Current`) with what it last applied on that
connection, and only if they differ runs:

```sql
SELECT set_config('tenant_kit.tenant_id', $1, <local>), set_config('tenant_kit.bypass', $2, <local>)
```

So the setting always reflects the tenant of the code that is about to run SQL,
whichever pooled connection that code holds. Values are bound parameters, not
interpolated. TenantKit forgets what it applied (and re-applies on the next
statement) after transaction boundaries, rollbacks and savepoint rollbacks
(which undo `set_config`), and `reset!` / `reconnect!` / `disconnect!`.

### Strategies

| | `:session` (default) | `:transaction` |
|---|---|---|
| `set_config` scope | session (`is_local = false`) | transaction (`is_local = true`, i.e. `SET LOCAL`) |
| Active Record connection pool | safe | safe |
| PgBouncer **session** pooling | safe | safe |
| PgBouncer **transaction** pooling | **not safe** | safe |
| Statements outside a transaction | see the tenant | see **no** tenant (fail closed); session values are cleared |
| Extra round trips | one per tenant change per connection | one per transaction |

**Why `:session` is unsafe behind PgBouncer transaction pooling:** PgBouncer may
hand each statement (each implicit transaction) to a different server
connection, so the `set_config` and the query that follows can land on
different backends — and a backend can keep another client's session value.

**Living with `:transaction`:** the tenant is only visible inside a
transaction. Autocommit reads return nothing and autocommit writes fail the
policy. Wrap request and job work in a transaction, for example:

```ruby
class ApplicationController < ActionController::Base
  around_action { |_, action| ActiveRecord::Base.transaction(&action) }
end
```

Be aware that holding a transaction for a whole request has its own costs
(longer-lived locks, a connection held throughout); many apps scope it to the
actions that touch tenant data.

## `without_tenant` under RLS

By default, `TenantKit.without_tenant` sets `tenant_kit.bypass = 'on'`, which
the generated policy honours. This keeps seeds, admin screens and data
migrations working unchanged.

The trade-off: the bypass is a setting your application role is allowed to
change, so code that can run arbitrary SQL as that role (e.g. through a SQL
injection with stacked statements) could set it too. If you want the database
to require a **different role** for cross-tenant work:

1. Generate the policy with `--no-bypass` and set `config.postgres_rls_bypass = false`.
2. Give unscoped work its own connection as a `BYPASSRLS` role, e.g. a second
   database configuration used through `connected_to(role: :admin)`:

   ```ruby
   # config/database.yml: an `admin` entry with a BYPASSRLS user
   ActiveRecord::Base.connected_to(role: :admin) do
     TenantKit.without_tenant { Report.rebuild_all! }
   end
   ```

With the bypass disabled, `without_tenant` on the normal connection returns no
rows from RLS tables — fail closed.

## Trade-offs and limitations

- **Not a substitute for TenantKit scoping.** Keep the Active Record layer: it
  raises loudly in development (`NoTenantSet`), RLS fails quietly (empty
  results). RLS catches what slips through.
- **Superuser / `BYPASSRLS` connections ignore policies.** See setup step 3.
- **`connection.raw_connection` bypasses the sync.** SQL sent straight to the
  `PG::Connection` runs with whatever was last applied on that connection.
- **Background threads have no `Current` tenant.** `load_async` with an async
  executor, or a `Thread.new` that queries, runs with no tenant and sees no RLS
  rows.
- **Unique constraints are global.** A unique index on `slug` still reports a
  conflict caused by another tenant's row (a small existence side channel). Put
  the tenant column in unique indexes, as TenantKit already recommends.
- **Foreign-key checks are not filtered by RLS** (PostgreSQL runs them
  internally). Tenant consistency between parent and child rows still relies on
  validations and composite constraints.
- **Performance.** The policy adds the same tenant predicate TenantKit already
  adds, so plans are usually unchanged; the cost is one `set_config` round trip
  per tenant change per connection (`:session`) or per transaction
  (`:transaction`).
- **Schema dumps.** `db/schema.rb` does not record policies. Use
  `config.active_record.schema_format = :sql` (`structure.sql`) so test
  databases get them, or re-run the RLS migration in your test setup.
- **Multiple databases.** The hook applies to every PostgreSQL connection;
  tables without a policy are unaffected.
