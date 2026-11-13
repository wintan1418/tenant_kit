# AGENTS.md — working on TenantKit

Guidance for AI coding assistants (and humans) changing this repository.
TenantKit protects a security boundary: **default to strict, fail-closed
behaviour and prove every isolation claim with a spec.**

## Layout

- `lib/tenant_kit.rb` — entry point, `with_tenant` / `without_tenant`.
- `lib/tenant_kit/model.rb` — `belongs_to_tenant`, `TenantPredicate`, write guards (`InsertAllGuard`, `CounterGuard`, cross-tenant validation).
- `lib/tenant_kit/explicit_scoping.rb` — `scoping: :explicit` and its guard.
- `lib/tenant_kit/job.rb` — ActiveJob propagation and argument verification.
- `lib/tenant_kit/streams.rb`, `cable.rb`, `turbo.rb` — realtime helpers (turbo-rails optional).
- `lib/tenant_kit/postgres_rls.rb` + `lib/generators/tenant_kit/rls/` — PostgreSQL Row-Level Security.
- `spec/leaks/` — adversarial isolation specs (shared context `"two tenants"` in `spec/support/two_tenants.rb`).
- `spec/postgres_rls/` — RLS specs, tagged `postgresql: true`.
- `spec/dummy/` — host app; schema in `spec/support/schema.rb` (reloaded every run).
- `docs/GUARANTEES.md` — the contract; every link must point at an `it` line (enforced by `spec/tenant_kit/guarantees_doc_spec.rb`).

## Commands

```bash
bundle install
bundle exec rspec                                   # SQLite, newest Rails
DB=postgresql bundle exec rspec                     # PostgreSQL (+ RLS specs)
DB=mysql bundle exec rspec                          # MySQL via trilogy (DB_HOST/DB_USERNAME/DB_PASSWORD)
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile bundle exec rspec   # a specific Rails series
bin/matrix                                          # all Rails gemfiles x sqlite,postgresql
COVERAGE=false bundle exec rspec spec/leaks         # fast loop, no SimpleCov
bundle exec rubocop
```

CI matrix: Ruby 3.3, 3.4 × Rails 7.2, 8.0, 8.1 × sqlite, postgresql, mysql;
line coverage ≥ 90% per job (`MIN_COVERAGE`), RuboCop, gem build.

## Conventions

- Write the failing spec first. New isolation behaviour goes in `spec/leaks/`
  and gets a row in `docs/GUARANTEES.md` with a `spec/...#Lnn` link. If you
  move spec lines, fix the links (the doc spec will tell you).
- Strict by default. Anything more permissive must be opt-in configuration.
- Behaviour changes for existing users need an **Upgrade notes** entry in `CHANGELOG.md`.
- Runtime dependencies: only activerecord, activesupport, railties. Don't
  require turbo-rails, actioncable or pg at load time.
- Private Rails APIs are touched in exactly two places — `with_raw_connection`
  (RLS hook) and `ActiveRecord::InsertAll#initialize` — both identical on Rails
  7.2–8.1. If you add another, test it on every gemfile.
- Style: rubocop-rails-omakase. Short imperative commit messages, no trailers.

## Releasing

Only the maintainer releases.

1. On `main` with green CI: confirm `lib/tenant_kit/version.rb` and the
   `CHANGELOG.md` heading/date and compare links.
2. `bundle exec rake build` → `pkg/tenant_kit-X.Y.Z.gem`.
3. `bundle exec rake release` (tags `vX.Y.Z`, pushes the tag, pushes the gem; MFA required).
4. Create a GitHub release from the tag with the CHANGELOG section.
