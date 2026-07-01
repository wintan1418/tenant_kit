# CLAUDE.md — Build Instructions for `tenant_kit`

You are building a Ruby gem, not a Rails application. Read `MASTER_BUILD.md` in
full before writing any code. It is the authoritative spec. This file tells you
*how to work*.

## What you are building

A row-level (shared-schema) multi-tenancy gem for Rails 8 called `tenant_kit`,
built on `ActiveSupport::CurrentAttributes`, with background-job tenant
propagation. Full design is in `MASTER_BUILD.md`.

## How to start (this answers "is it a normal Rails app?" — it is not)

```bash
rails plugin new tenant_kit --dummy-path=spec/dummy -T
cd tenant_kit
```

- `rails plugin new` (NOT `rails new`) scaffolds the gem plus a throwaway host
  app under `spec/dummy`. You develop and test *against* that dummy app.
- `-T` skips the default test unit; you will add RSpec.
- The gem hooks into Rails through `lib/tenant_kit/railtie.rb`. No full Engine.

Then:
1. Add `rspec-rails`, `standard` (or rubocop-rails-omakase), and Rails 8 to the
   gemspec/Gemfile as development deps. Runtime deps: `railties`, `activerecord`,
   `activesupport` ONLY.
2. `rails g rspec:install` inside context; wire `spec/dummy` into `rails_helper`.
3. In `spec/dummy`, define `Account` (tenant), `Project` and `Invoice` (owned)
   models plus migrations, so the specs have something to run against.

## Build order — do these in sequence, tests green before advancing

Follow §9 of `MASTER_BUILD.md` exactly:
1. Skeleton (boots, RSpec runs)
2. Model core (`belongs_to_tenant`, scoping, auto-assign, `with_/without_tenant`)
3. Uniqueness + strict mode
4. Controller resolution helpers
5. Job propagation (`TenantKit::Job`)
6. Generators (`install`, `migration`)
7. Docs + lint polish

Write the spec for a milestone first, then the implementation, then make it green.

## Hard rules — do not violate

- **NEVER use `Thread.current` for tenant state.** Use `TenantKit::Current`
  (`ActiveSupport::CurrentAttributes`). A grep for `Thread.current` in the final
  gem must return nothing.
- **Auto-assign the tenant via `before_validation`**, not via `default_scope`
  create behavior.
- **Strict by default.** With `require_tenant = true` and no tenant set (and not
  inside `without_tenant`), a tenant-scoped query must raise
  `TenantKit::NoTenantSet`.
- **Unique constraints include the tenant column** at both DB and validation level.
- **No runtime dependencies beyond Rails.** If you think you need another gem,
  STOP and leave a `# TODO(review):` note instead of adding it.
- **Do not build anything in §11 "out of scope."** No schema-per-tenant, no DB
  UI, no caching helpers. Row-level core only.
- **Do not invent features not in `MASTER_BUILD.md`.** If the spec is ambiguous,
  implement the simplest correct behavior and leave a `# NOTE:` comment
  explaining the choice, rather than expanding scope.

## `default_scope` is sharp — pin it with tests

`default_scope` interacts subtly with `unscoped`, associations,
`find_or_create_by`, and `create`. Do not trust it by reading — prove it with
`scoping_spec.rb`, `strict_mode_spec.rb`, and `job_propagation_spec.rb`. If a
behavior surprises you, the test is right and the implementation changes.

## Job propagation — the part most likely to break

`TenantKit::Job` must round-trip the tenant's GlobalID through ActiveJob
serialization so the tenant survives being enqueued into Solid Queue and
restored at `perform`. Prove it end to end in `job_propagation_spec.rb` with a
real enqueue → `perform_enqueued_jobs` cycle, asserting the tenant inside the
job and that it resets afterward. Do not mark milestone 5 done on a mocked test.

## Definition of done

- All specs green (see §8 of `MASTER_BUILD.md`).
- No `Thread.current` anywhere.
- Zero runtime deps beyond Rails.
- `standardrb`/rubocop clean.
- README complete, including the "Gotchas" section (Action Cable stream naming,
  `unscoped`, console/seed usage of `without_tenant`).
- `install` and `migration` generators produce working files in a fresh dummy app.
- YARD comments on every public method.

## Git & commit conventions

- **Commit milestone by milestone.** Each milestone in the build order is a
  self-contained commit whose specs are green before it lands. Never bundle two
  milestones into one commit.
- **No co-authorship trailers.** Commit messages must NOT contain
  `Co-Authored-By:` or any "Generated with" attribution. Write plain,
  descriptive messages in the imperative mood, e.g. `Add belongs_to_tenant
  scoping and auto-assignment`.
- **Message shape:** a concise subject line (≤ 72 chars) plus, when useful, a
  short body explaining *what milestone* landed and *which specs* now pass.
- **Green before commit.** Run `bundle exec rspec` and, from milestone 7 on,
  `bundle exec rubocop` before every commit. Do not commit a red suite.
- **Push after each milestone** to `origin main`.
- The remote is `github.com/wintan1418/tenant_kit`. Do not force-push `main`.

## Project-specific facts (already decided — do not re-litigate)

- Ruby target `>= 3.3`; Rails `>= 7.2`, primary target `8.x`.
- Tenant model: `Account`; tenant column: `account_id` (both configurable).
- Lint: `rubocop-rails-omakase` (already wired via `.rubocop.yml`). Stay with it.
- Runtime deps: `activerecord`, `activesupport`, `railties` only.
- Test DB: sqlite; schema is force-loaded from `spec/support/schema.rb` by
  `spec/rails_helper.rb`. Dummy app lives in `spec/dummy`.
- The dummy app defines `Account` (tenant), `Project` and `Invoice` (owned).

## When you finish

Print a short summary of: what was built per milestone, the final test count and
pass status, any `# TODO(review):` / `# NOTE:` markers you left, and the exact
commands to run the test suite and the two generators. Do not publish to
RubyGems — leave that to the human.
